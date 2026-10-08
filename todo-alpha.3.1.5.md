# Alpha 3.1.5 - Phased Implementation Plan

**Status: ACTIVE - PHASE A ACCEPTED; PHASE B IN PROGRESS.**

Planning requested and the decisions below confirmed by the user on 2026-10-06.
This document replaces the initial feature sketch, not the accepted Alpha 3.1.0
history. A request to prepare this plan does not start implementation, authorize
production builds or authorize Workshop publication.

The user authorized implementation on 2026-10-06 after adding the new edge tiles.
This is now the active tracker in [AGENTS.md](AGENTS.md); version/changelog report
Alpha 3.1.5 in development. Alpha 3.1.0 remains accepted historical development.
No phases below are accepted merely because their design is agreed.

### Follow-up decision - recipe count and authoring pause

On 2026-10-06 the user confirmed that any necessary coast/edge recipe-count
increase is acceptable. Preserve the approved geometry/coast design rather than
reducing its scope merely to avoid additional maps. Reuse existing water-border
recipe signatures where sufficient; report actual before/after unique recipe
counts, BSP/model bytes and build costs when implementation runs.

World content already has separate Workshop packaging/sharding. Continue to
enforce measured shard budgets, dependency closure and Source compiler/runtime
limits; an unrestricted map-count assumption is not a verified engine guarantee.
This decision does not authorize uploads or production rebuilds.

**Historical authoring pause (lifted):** the user was adding more edge tiles and would
explicitly announce when to implement Alpha 3.1.5. Do not regenerate, compile,
stage or activate the milestone while waiting. That go-ahead was subsequently
given on 2026-10-06; Phase 0 re-inventoried the final authored edge set.

## 1. Locked design decisions

### 1.1 Cell geometry, coordinates and coast

- Keep the logical world grid, cell addresses, 5x5 core tile assignments, difficulty,
  profile scoping and destination relationships unchanged.
- Add a new one-tile outer edge ring outside the existing one-tile border ring.
  Maximum visual footprint: **5x5 core + border + edge = 9x9 tiles**.
- Tile size stays 640 Hammer units. In the current centred coordinate system:

  | Domain | Tile coordinates | Physical XY extent | Purpose |
  | --- | --- | --- | --- |
  | Core | 0..4 | -1600..1600 | Existing gameplay/spawn domain |
  | Existing border | perimeter of -1..5 | -2240..2240 | Traversable wherever authored geometry permits |
  | New outer edge | perimeter of -2..6 | -2880..2880 maximum | Scenery, not an expanded gameplay grid |
  | Neighbour visual pitch | one logical cell step | 5760 units | Full 9-tile skyline spacing |

- Physical instance origins remain centred on the original core:
  `x = (tileX - 2) * 640`, `y = (2 - tileY) * 640`. Do not shift all existing
  instances merely because the visual footprint is larger.
- New straight edge buildings face **inward toward the existing border**.
  The user describes their authored facing as north, opposite the existing
  south-facing building convention. Inspect the actual source before assigning yaw.
- Existing border is traversable but gets **no new loot, harvestables or walker
  spawns**. Existing walkers may pursue onto reachable border geometry; it is not
  a player-only refuge. The outer edge is scenery only and must be inaccessible.
- Land-facing sides get outer edges. As clarified 2026-10-07, only the
  **west 3D-skybox ocean boundary** omits outer building/fill pieces; separate
  authored water-corner border choices do not cause edge-layer omissions.
  **Ocean must still meet the existing border, not move outward
  to the new 2880-unit visual limit.**
- A valid road/bridge exit is the narrow exception on a water side: extend its
  matching route corridor through the outer slot, without adding a strip of land
  or moving the shoreline along the rest of that side.
- Omit new NW/SW outer corners touching the west ocean side. Keep existing coast corners
  unchanged. Fully land-facing outer corners use the new edge corner.
- Future docks/harbour assets and mixed land/water outer-corner artwork are
  explicitly deferred. Do not invent substitutes in this milestone.
- Preserve existing carpark caps, water tips/piers, ramp/bridge heights and
  safe-zone entrance suppression. Outer geometry must not obstruct their access.

### 1.2 Environment-specific edges

- Match existing border environment mapping:
  `radioactive -> ra`, `military -> army`, `fortified -> army`; other environments
  use the default edge pool.
- A matching tagged pool **replaces**, rather than mixes with, the default pool
  for that piece kind. Select deterministically within the winning pool.
- Resolve straight pieces and corners independently. Missing tagged corner means
  default corner only; it does not discard matching tagged straight pieces.
- Water omission and route/safe-zone reservations take precedence over environment
  selection. Environment tags cannot put a building over a bridge, coast or door.
- Source inventory observed during planning:
  [edges](tiletemplates/edges) contains `tile_edge_wall_1a.vmf`,
  `tile_edge_wall_1aa.vmf`, `tile_edge_wall_corner.vmf`,
  `tile_edge_ra_none.vmf` and `tile_edge_army_none.vmf`.
  Re-scan at implementation start: the user is actively authoring these assets.
- Do not interpret `_none` as "omit the tile": it is an authored asset name.
  Do not treat editor `.vmx` backups, including the old-named corner companion,
  as selectable templates or rename/delete them without the user's approval.

### 1.3 Travel gates and road arrows

- Move road exit gates to the boundary between existing border and new edge,
  **not** the far outside of the new edge ring.
- Keep E-to-travel, server authority, existing eligibility checks, logical
  destination, departure fade, loading lifecycle and arrival walk.
- Move the opposite-side arrival anchor consistently. Travelling between logical
  cells sharing a BSP must still reload and persist the new coordinates.
- At route exits, outer slots use matching road/motorway/bridge continuations
  instead of buildings; preserve the correct elevation and cardinal alignment.
- One **static flat road arrow per gate**, 192 units long in the outward direction
  and 128 units across. No flashing, pulsing or repeated arrow trail.
- Colours: existing normal green, waypoint-route yellow, blocked red.
  Draw within 1280 units, depth-tested and hidden by world geometry.
- Position just above the real road surface to prevent z-fighting. Do not project
  a bridge arrow onto ground beneath it. Existing nearby E prompt remains separate.
- This intentionally changes the requested marker from a floating sprite to a
  ground arrow. Diagnose current ownership first, then prevent duplicate old
  sprites/markers rather than layering a second marker system over them.

### 1.4 Map surfaces

- Include the full border/edge footprint in **all three** affected surfaces:
  HUD minimap, world-map cell artwork/previews, and current-level satellite capture.
- Logical world grid size and clickable cell boundaries remain unchanged.
  A cell's picture grows in coverage; it does not acquire extra logical cells.
- Use the same generated placement/extent metadata for artwork and projections.
  Player, loot, doors, route arrows, NPCs and waypoints must still align.
- Coast omissions remain visible as water, not fake land or a cropped blank edge.
- Preserve den-specific capture coverage and all current map-mode/input behavior.

### 1.5 Movement and loot

- Walking is 25% slower **than current implemented walking**:
  `0.90 * 0.75 = 0.675` times the unmodified base speed.
- Sprint is 10% slower **than current implemented sprinting**:
  `0.85 * 0.90 = 0.765` times the unmodified base speed.
- Preserve implant bonuses, stamina drain/recovery/max, exhaustion input handling,
  sprint-held-while-stationary behavior and noncompounding spawn/refresh logic.
  Scripted transition movement is not ordinary walk/sprint and stays unchanged.
- Rarity affects searchable map props and placed fallen bodies only.
  **Enemy/boss drops, player drops, harvesting, item quality and stack sizes stay
  unchanged.**
- Matching props use half their current activation probability.
  Fallen-body placement changes from 2-4 to **1-2 bodies per cell**.
- All active searchable prop/body spots selected on a new generation must have
  at least **320 units of 3D straight-line separation between search centres**.
  Exactly 320 is allowed. Do not impose an XY-only exclusion across separate floors.
- Keep the existing five-minute absence refresh rule. Existing persisted cell
  loot is not rerolled, culled or rewritten merely on upgrade/reload; apply new
  rules at the next normal regeneration. Older saved clusters may remain until then.
- **Explicit rebuilt-map exception confirmed during planning:** a one-time,
  backed-up loot reset is allowed for cells whose actual map is rebuilt. Engine
  map-creation IDs and fallen-body layouts can change across a rebuild. Reset only
  affected profile/logical-cell loot, never character inventory/equipment.
  Unrebuilt cells keep the natural-refresh rule above.
- Border/outer scenery props must not become searchable just because their models
  match entity-loot rules. Preserve the original core spawn/search domain.

### 1.6 Launcher art direction and assets

- **Heavily distressed post-apocalyptic** art direction: damaged Earth/city,
  grungy panels and stronger horror mood, while retaining readable text and controls.
- Earth keeps recognisable real continents/coastlines. Cosmetic blackout/failed
  city lights, scorch overlays and smoky clouds provide damage.
  No invented story claims, exploding planet or server weather/gameplay changes.
- Use a texture-backed sphere, not a required separately authored globe model.
  Clearly distinct land/ocean, directional day/night lighting, detailed night
  lights, animated clouds and an atmospheric rim are in scope.
- Agent may source exact Earth/day/night/cloud assets from NASA or similarly
  explicit redistribution-permitted providers. Verify **each exact asset's**
  source, licence, third-party exceptions and attribution before staging.
  A provider's name is not blanket clearance.
- User will supply a new **Z-Nation logo**. Existing logos are not replacements.
  Animate only a slow subtle brightness/breathing effect; do not distort the
  artwork or use rapid flicker.
- High-detail globe is the default for new/reset preferences; retain a lower-cost
  quality mode. Preserve explicit existing user quality choices.
- Target a smooth **60 FPS on the user's machine**, validated with matched launcher
  workloads. Visual ambition is not permission for an unbounded laggy renderer.

### 1.7 Launcher navigation, city preview and cards

- Home has exactly four primary actions: **Play, Tools, Settings, Exit**.
  Logo/globe are presentation; Reset View is a contextual globe control, not a
  fifth primary navigation action. Preserve required first-run/content briefings.
- Play changes the left pane into a character grid and zooms the right scene from
  recognisable Earth into a **stylised fictional city**, using the active profile's
  actual generated skyline where suitable. This is not a promise of geographically
  accurate London/New York buildings or seamless real-world city reconstruction.
- Three slots remain profile-scoped. Occupied card click selects/previews; only an
  explicit **Deploy** action requests deployment. Empty cards start Create.
- Play initially highlights the last active survivor without deploying.
  No survivor means starting region and empty Create cards.
- Selected scene centres on the **current saved resume cell**, not birth/origin.
  If saved in a den, use its owning city cell plus den label, not a fake interior.
  Undeployed characters use their defined starting location.
- Full-body card thumbnails show saved model/skin/bodygroups/player colour,
  current worn clothing and saved active weapon. Do not show inactive weapons or
  inventory contents. Labels: name, profession, level, resume location.
- Cache accurate thumbnails; rebuild on appearance/equipment changes rather than
  continuously rendering three animated models.
- Read-only per-character snapshots obtain these details without selecting/loading
  another survivor, changing active ownership or touching saved equipment.
- Legacy appearance-required characters show **Set Appearance** explicitly;
  never invent a completed outfit or enable Deploy prematurely.
- Camera durations: Earth-to-city 3 seconds, character pan 1 second, Back-to-Earth
  2 seconds. Controls remain responsive. Retarget from current interpolated pose;
  never queue a backlog of pans.
- Home Earth only: left-drag rotates, wheel zooms with bounded camera distance;
  Reset View restores automatic framing. Selection/automatic navigation retakes
  framing. No drag/zoom interception over left-pane controls; no click-to-travel.
- Credits and Content Addons move under Settings in **both** profiles.
  Tools is visible in both; preview-only actions remain disabled in city.
  Showing Tools must not weaken Wardrobe/development/admin guards.
- Keep Create/appearance wizard, typed-name delete confirmation, content deployment
  gates, Exit disconnect confirmation and existing settings/sky-browser behavior.
- Both profiles are in scope. Missing production skyline assets are an explicit
  blocker for city-scene acceptance, not permission to fake assets or rebuild city.

## 2. Scope exclusions and approval rules

- No additional character slots, real-world city data, new storyline, new music,
  harbour/dock assets, gameplay weather changes or automatic travel.
- No Walker simulation redesign, pool-capacity increase, clothing catalogue
  expansion, gore redesign or re-opening accepted Alpha 3.1.0 phases.
- Keep the isolated C++ Walker project independent. Change its integration only if
  evidence proves the new traversal contract requires it; do not add GLua/assets
  to the C++ project. Native edits require the documented focused CMake/CTest checks.
- Shared source supports city and preview, but world-output work is **preview first**.
  Obtain separate approval before any production city rebuild/promotion.
- Workshop publication, IDs, rights not related to new assets, missing release
  navmeshes and clean-download/mount gates remain separate deferred release work.
  Preview pursuit/traversal may require updated preview navmeshes; that is not
  permission to generate every missing production release navmesh.
- Never hand-edit generated plans, VMFs, BSPs, manifests, models or map materials.
  Preserve unrelated work and user-authored templates.
- A phase gets static checks as it lands, then its actual live/visual checks.
  **Only the user accepts a phase.** Record unverified/deferred checks honestly.

## 3. Source map and known coupling

These owners were inspected during planning. Re-read affected code before editing;
line numbers and implementation details can change.

| Surface | Existing owners | Important coupling |
| --- | --- | --- |
| Profile/settings | [generator-settings.json](generator-settings.json), [resolver](bin/resolve_world_generation_profile.ps1) | Do not infer paths/settings from names |
| Recipe/border/gates | [VMF builder](bin/build_cell_vmfs.ps1), [planner](bin/plan_cell_templates.ps1) | `Get-BorderPlacements`, `Get-BorderTemplateSet`, `Get-TransitionGates`, sky-room coverage, structure validation |
| Authored bounds/assets | [base template](celltemplates/template_border_s.vmf), [edges](tiletemplates/edges), [border](tiletemplates/border) | Seals/clip planes may still assume the old footprint |
| Carparks/entrances | [cap helper](bin/carpark_endcaps.psm1), [entrance tests](bin/test_safezone_entrances.ps1) | Preserve canonical cap/suppression rules |
| Skyline output/runtime | [model builder](bin/build_skybox_models.ps1), [model helpers](bin/skybox_models.psm1), [client skybox](gamemode/cl_skybox.lua) | Current model/room pitch is `(gridSize + 2) * tileSize`, not the HUD's 3200 |
| Map output | [cell artwork](bin/build_cell_map_materials.ps1), [staging](bin/stage_world_map_materials.ps1), [satellite stitcher](bin/build_world_satellite_material.ps1), [runtime export](bin/export_runtime_world_data.ps1) | Artwork currently follows core placements; must share new extents |
| Runtime world lookup | [world utility](gamemode/utils/world.lua) | Own logical coordinates, profile/map resolution and new bounds API |
| Travel | [server transitions](gamemode/sv_transitions.lua), [client transitions](gamemode/cl_transitions.lua) | Gate globals/prompts, arrival records, same-BSP travel and fade lifecycle |
| Minimap/map | [HUD](gamemode/cl_hud.lua), [world map](gamemode/cl_world_map.lua), [map batch](gamemode/cl_map_batch.lua) | HUD has 1600 half-extent; capture uses separate derived span/cache version |
| Movement | [movement](gamemode/sv_movement.lua), [tests](gamemode/tests/sv_movement_tests.lua) | Baseline capture and implant refresh must not compound |
| Loot | [spots](gamemode/sv_loot_spots.lua), [bodies](gamemode/sv_loot_bodies.lua), [rolls](gamemode/sv_loot.lua), [SQL](gamemode/utils/sql.lua) | Independent activation currently has no inter-spot spacing; atomic cell replacement |
| Spawn/harvest bounds | [foliage](gamemode/sv_foliage.lua), [enemies](gamemode/sv_enemies.lua) | World AABB includes sky-room geometry; do not use visual bounds for spawns |
| Menu/scene | [menu](gamemode/cl_launcher_menu.lua), [client scene](gamemode/cl_launcher_scene.lua), [shared scene](gamemode/sh_launcher_scene.lua), [server launcher](gamemode/sv_launcher.lua) | Main-scene camera, globe, previews, PVS, credits and sky inspection ownership |
| Characters/persistence | [characters](gamemode/sv_characters.lua), [inventory](gamemode/sv_inventory.lua), [SQL](gamemode/utils/sql.lua) | Current `List` lacks full appearance/equipment/resume snapshot |
| Clothing previews | [clothing](gamemode/cl_clothing.lua), [composition](gamemode/cl_clothing_preview.lua) | Shared bounded pool; card entities must pin/release correctly |
| Tools/settings | [Tools](gamemode/cl_launcher_tools.lua), [Options](gamemode/cl_quick_menu.lua) | Tools currently preview-only and atlas path hardcodes preview |
| Profiling/distribution | [profiler](gamemode/cl_dev_profiler.lua), [package builder](bin/build_workshop_packages.ps1), [package fixtures](bin/test_workshop_packages.ps1) | Hook CPU is not total GPU/frame cost; new assets need allowlisted ownership |

### Read before edits

[AGENTS.md](AGENTS.md), [README](readme.md), [generator guide](docs.md),
[game design](docs/gdd.md), [tile instructions](.github/instructions/tiletemplates.instructions.md),
[rendering instructions](.github/instructions/client-rendering.instructions.md).
Load the world-build skill for generator/map work. Consult current GMod/VDC
documentation for unfamiliar APIs and record non-obvious engine findings.

## 4. Phase order and dependency graph

Work in the order below. A dependency is real prerequisite evidence, not just a
suggested parallel work queue. Do not defer a failed phase check until integration.

| Phase | Deliverable | Prerequisites |
| --- | --- | --- |
| 0 | Baselines, source/asset inventory and implementation activation | User authorizes implementation |
| A | Shared extent contract and outer-ring geometry | 0 |
| B | Skyline spacing and coast preservation | A |
| C | Relocated gates, arrivals and flat markers | A, B |
| D | Border-aware map artwork/capture/projection | A, B, C |
| E | Movement and spaced rarer loot | A, C |
| F | Read-only character snapshots and cached outfit thumbnails | 0 |
| G | Texture-backed Earth and bounded city-preview renderer | B, D, F; asset clearance |
| H | New menu flow, camera transitions, Tools/Settings and logo | F, G; supplied logo |
| I | Integrated preview acceptance, approved city rollout and close-out | A-H |

Phase F is architecturally independent of E, but preserve this working order for
one-agent continuation. The new logo is an H blocker, not an excuse to guess art
or stop unrelated geometry work. City rollout is deliberately last and gated.

## Phase 0 - Activate, capture and establish reproducible inputs

**Objective:** start from known source/profile/runtime state, not stale generated
files or a repeated milestone-wide audit.

- [x] Obtain implementation go-ahead. Update active tracker, version/changelog
  and README consistently; do not mark released.
- [x] Record dirty paths and preserve user edge/Hammer saves. Re-scan edge assets,
  inspect footprint/facing/height/materials, and identify environment variants.
  Static source inventory is complete; visual facing/joins await Hammer inspection
  in Phase A and are not claimed verified by a filename or missing direction marker.
- [x] Resolve preview settings through the resolver. Record exact manifest,
  plan/recipe IDs, seed, current core/border span, sky camera and base seals.
- [x] Establish a deterministic small fixture covering default land, radioactive,
  military, fortified, all four exits, motorway, ramp/bridge, carpark, safe-zone
  entrance, one water side, adjacent water sides and mixed corner.
- [x] Retain known-good preview outputs/restoration path for isolated comparison.
  Do not regenerate production or delete old unowned assets.
- [x] Plan a verified logical backup of cell-loot rows before any rebuilt-map
  reset. Record old/new map fingerprints and affected profile/cell references;
  recipe reuse means one rebuilt BSP may affect several logical cells.
- [ ] Record launcher profile/map, graphics/globe quality, resolution, camera,
  background populations/effects and cold/warm state for performance baselines.
  Capture home/menu navigation and a representative core/border/coast/gate view.
  A fresh existing-gameplay capture/profile is retained; launcher/coast/gate
  scene/profile was subsequently retained after the user opened the launcher.
  Coast/gate views, full quality snapshot and controlled cold-warm evidence remain
  pending. Agent did not move the player or change maps.
- [x] Inventory new globe texture candidates; retain exact licences/source URLs.
  Request supplied logo as a source-art dependency, including transparent
  background/high-resolution original. Do not require an invented replacement.
  Candidate pages/usage conditions and inaccessible endpoints are recorded below;
  no image is staged or cleared for redistribution yet. Supplied logo is pending.
- [x] Record missing production skyline/runtime assets without fixing them yet.
- [x] Save a checkpoint with inputs, limits and next phase; no historical F/G/H redo.

**Gate:** reproducible fixture/known-good baseline and explicit asset/build blockers
recorded. Final Earth and logo appearance wait for their own prototypes.

### Phase 0 evidence - 2026-10-06

**Phase 0 accepted by the user on 2026-10-06 with explicit baseline limits carried
forward. No Phase A changes,
world regeneration, BSP compilation, production rebuild or user-data migration.**

The user explicitly carried remaining coast/gate photographs and the full
quality/cold-warm baseline into relevant Phase A/B/G checks. The unchecked
baseline-capture item above records that limitation, not an instruction to reopen
Phase 0. Phase A was the next implementation phase at that acceptance; its
current implementation/evidence ledger appears below.

- Preserved all existing work, including the user's modified border `.vmx`, new
  edge folder and prior Alpha 3.1.0 close-out changes.
- Resolved `preview`: 24x24 logical cells, seed 1337, 5x5 core, tile 640.
  Exact existing inputs:
  [manifest](bin/preview_grid_24x24_seed_1337.json),
  [plan](bin/preview_grid_24x24_seed_1337_template_plan.json),
  [required list](bin/preview_grid_24x24_seed_1337_required_cell_vmfs.txt).
  Current plan: 576 cells / 179 unique recipes; existing skyline pitch 4480,
  scale 16, camera Z 5120, detailed radius 2, skyline radius 24, tower cap 128.
- Base template winding/plane inspection identifies existing outer source envelope
  approximately +/-2304 XY and Z -32..4672, distinct from the intended 2240 border
  coverage. Phase A must inspect actual seal/clip brushes, not resize an assumed
  +/-2240 box blindly.
- Reused the existing 6x6 border-showcase input (seed 20260903) and planned it into
  **session storage only**, producing 36 cells / 18 recipes. Covers north/west
  water sides, NW water corner, far tips and mixed land/water corners.
- Created a session-local copy of that fixture with cell (5,5) tagged military;
  planner resolves `zz_preview_89a23c758e23.vmf` to military. No preview/world input
  was modified. Existing seed-1337 plan has zero military and water-border cases,
  so it cannot substitute for those fixture cases.
- Deterministic existing-plan selectors are retained for land, radioactive,
  fortified, motorway, bridge, ramp, carpark, safe-zone entrance and four exits.
  Examples: land `zz_preview_5882bf932adf.vmf`; radioactive
  `zz_preview_a6eb3090c263-v1.vmf`; fortified `zz_preview_425f308cc050.vmf`;
  carpark `zz_preview_f1ba4bf3c2cc-cp.vmf`; entrance
  `zz_preview_3d43c38020ac.vmf`. Exact raw/logical coordinates are in the session
  baseline report; resolve those records rather than guessing from names.
- Session artifacts: `alpha315-phase0-baseline.json` fingerprints 3761 paths;
  `alpha315-known-good-inventory.json` verifies **3936 copied files /
  2,248,287,711 bytes** in the session's `alpha315-known-good` directory.
  Copies include current preview VMF/BSP/nav output, skyline model companions/
  wrapper materials, source edges/settings/base and runtime inputs. Original
  installed/staged files remain untouched. This is restoration evidence, not a
  certification that every old output matches the latest authored source.
- Before Phase A overwrites additional resources (sky-room source, artwork, source
  dependencies or textures not in that inventory), extend the backup closure and
  verify hashes. Restore old map and cell-loot backup together if rolling back.
- Cell-loot reset implementation remains Phase E: logically back up
  `ZM_GetLootCell`/`ZM_GetLootSpots` data with schema/revision/profile/cell metadata,
  verified row counts/contents, then transactional reset exactly once per rebuilt
  revision. Fail closed on backup/SQL errors. No SQLite rows were changed in Phase 0.
- Production world export exists but requires its own compatibility/freshness
  validation. **No city skyline manifest exists**; keep production scene/build
  acceptance explicitly gated. No production regeneration was attempted.

#### Final authored edge inventory

All nine VMFs parse through the existing VMF parser and have `vertices_plus`
windings on every inspected brush side (zero missing windings). Bounds below are
actual brush winding envelopes, **excluding mounted prop-model extents**; material/
entity lists and SHA256 values are retained in the baseline JSON.
No `zn_tile_direction` markers were found: north-facing orientation still needs
source/Hammer visual verification, not inferred proof.

| VMF | Brush XY envelope | Brush Z range | Intended pool |
| --- | --- | --- | --- |
| `tile_edge_wall_1a.vmf` | -320..320 / -320..320 | 0..352 | Default straight |
| `tile_edge_wall_1aa.vmf` | -444..480 / -364..320 | ~0..1712 | Default tall straight |
| `tile_edge_wall_corner.vmf` | -320..320 / -384..320 | ~0..432 | Default corner |
| `tile_edge_ra_none.vmf` | -320..320 / -320..320 | 0..32 | Radioactive straight |
| `tile_edge_ra_wall_1a.vmf` | -320..320 / -320..320 | 0..444 | Radioactive straight |
| `tile_edge_ra_wall_1aa.vmf` | -320..320 / -320..320 | 0..444 | Radioactive straight |
| `tile_edge_army_none.vmf` | -317.458..322.542 / -320..320 | ~0..32 | Army straight |
| `tile_edge_army_wall_1a.vmf` | -320..320 / -320..320 | 0..704 | Army straight |
| `tile_edge_army_wall_1aa.vmf` | -317.458..322.542 / -320..320 | ~0..288 | Army straight |

User explicitly confirmed the tall/default-corner overhangs are intentional:
**preserve them and test neighbour joins/clearance; do not trim them**.
Preserve the small army-source X offsets too until exact source/instance evidence
shows a required correction. No tagged corners exist, so default-corner fallback
remains required. Editor `.vmx` files were retained and excluded from selection.

#### Runtime baseline captured, not a launcher-performance verdict

- Fresh capture `alpha315-phase0-gameplay`, timestamp 1791316336:
  map `zz_preview_e505a3e027e3-v2`, preview raw grid (22,14), logical (22,2) under
  the recorded preview origin. 1366x768; camera origin
  (233.8597,192.4805,108.0312), forward (-0.9499,-0.211,-0.2306).
- Rain, dusk context; sky detail 2, props ~0.7, fires enabled, light scale 0.25.
  Captured frame counts: 19 nearby models, 28 tower parts, 139 props, 28 fires.
- Fresh 15-second profile: 298 frames, 19.905 FPS, median 49.969ms,
  p95 55.834ms, p99 58.542ms, maximum 134.167ms; measured hook CPU 8.497ms/frame.
  This is **pre-change gameplay operation evidence**, not a globe/menu baseline,
  a matched comparison, a GPU attribution or evidence that this task caused lag.
- Hook report has no embedded timestamp: retained copied report/hash and file
  modification time after the acknowledged capture/profile request. Do not confuse
  older console.log entries with the current running session.
- No survivor movement, profile change, cheat/preference change or map reload was
  performed by the agent. The user subsequently opened `zn_preview_start`.
- Fresh launcher scene capture timestamp 1791316864: camera (0,-160,112),
  forward (0,1,0), sky inspection inactive. The stock screenshot hook captures
  the world/globe before primary-menu VGUI; it is a **scene-only** baseline,
  not evidence that the full menu UI was captured.
- Initial launcher sample: 307 frames / 20.450 FPS / median 49.956ms. The user
  confirmed GMod was unfocused: retain this and the earlier gameplay sample as
  background operation evidence, **exclude them from focused FPS comparisons**.
- User then kept the launcher focused for a repeat after a five-second focus-switch
  allowance. Fresh 15-second sample: 746 frames, 49.764 FPS, median 17.655ms,
  p95 36.009ms, p99 40.396ms, max 44.661ms; measured hook CPU 16.221ms/frame;
  approximate positive Lua allocation 2507.279 KiB/frame. Retained separately as
  `alpha315-phase0-launcher-focused-profile.json`.
  This is a pre-change focused launcher baseline, not acceptance of the future
  60-FPS target or a GPU attribution. Do not fix its renderer in Phase 0.
- Full runtime quality/globe convar snapshot, controlled cold/warm labels and
  representative coast/gate captures remain unverified. Candidate asset licences
  and supplied logo remain later-phase blockers, not assumed approvals.

#### Globe provenance shortlist / logo dependency

- NASA [Blue marble](https://science.nasa.gov/resource/blue-marble/) page was
  reachable and describes the 2002 MODIS Earth mosaic. Exact separate day/cloud
  source downloads and credits still need verification.
- NASA [Earth at Night](https://science.nasa.gov/resource/earth-at-night/) page was
  reachable and describes a global composite. Treat as a candidate, not approved
  game-ready equirectangular/night-light texture.
- NASA [media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)
  were read: acknowledge NASA, avoid endorsement, distinguish protected branding
  and third-party images, and examine product/commercial-use conditions.
  **No blanket NASA/public-domain clearance is claimed.**
- SVS 2915/API and 30876 fetches failed; the older Visible Earth URL redirected to
  a generic Earth Observatory page. Retain those access limits. Cloud texture
  candidate remains unverified; no third-party replacement or asset import.
- User-supplied transparent, high-resolution Z-Nation logo is still required for
  Phase H. Do not substitute existing logo artwork.

## Phase A - Shared bounds and outer edge geometry

**Objective:** one authoritative distinction between logical core, traversal,
visual footprint, neighbour pitch and coast boundary.

Implementation notes:

1. Introduce profile-resolved outer-edge configuration alongside existing border
   configuration. Store explicit default/tagged straight/corner pools and validate
   source paths. Reuse existing deterministic variation/mapping patterns.
2. Use shared generated placement metadata for borders/outer edges, route
   reservations, environment selection and extent masks; VMF and artwork must not
   independently reimplement competing placement rules.
3. Expose validated runtime bounds through `ZM_World`. Distinguish core spawn
   bounds (3200), accessible border envelope (4480, constrained by real geometry),
   visual pitch (5760), per-side coast edge and ceiling. Do not redefine every
   existing `cellSpan` use as 5760 without auditing its meaning.
4. New-ring perimeter is tile coordinates -2..6: 32 possible slots before omissions
   and reservations. Existing ring remains -1..5: 24 possible slots before
   entrance suppression. Core placements/IDs/frontage remain unchanged.
5. Selection priority: protected entrance/reservation -> route corridor ->
   water/mixed-corner omission -> matching environment piece -> default piece.
   Diagnose missing required default assets; do not silently emit a hole.
6. For a verified north-facing straight source, inward yaws derive as
   `N=180, E=90, S=0, W=270`. This is a derivation to verify against the actual
   authored source in Hammer, not permission to apply a guessed global offset.
   Inspect corner source independently; do not reuse the border-corner yaw table
   just because names resemble one another.
7. Expand source base sealing/sky/clip geometry where needed to contain 9 tiles.
   Keep sky-room separation and Source coordinate/portal constraints intact.
   Remove only blocking boundaries tightly coupled to the approved accessible
   border, and place outer access restrictions so road travel remains possible.
8. Gate migration changes the passage corridor: inspect authored transition-road
   clip/barrier geometry and ensure the old core/border boundary is no longer an
   invisible wall. Preserve unrelated template art and sibling variations.
9. Recipe identity/stamps must reflect new placements/settings/source dependencies.
   Preserve incremental builds; do not disguise incompatible output as an old
   identical recipe. Generated metadata belongs to the pipeline.
10. Preserve core-only spawn/loot/harvest eligibility while making border traversal
    possible. Do not crop pursuit navmesh to the core just to exclude spawning.

Checks / acceptance:

- [x] Focused regression for exact ring coordinates/counts, four inward facings,
  all environment precedence/fallback combinations and deterministic selection.
- [x] Water sides/mixed corners omitted; route-only waterfront exception retained.
  Core assignments, carpark caps, entrance suppression and source yaw unaffected.
- [ ] Existing border gameplay exclusions and outer access restrictions asserted.
- [x] Run border showcase and safe-zone entrance tests; frontage/multi-tile tests
  when adjacency/frontage emission is affected. Refresh relevant tile zoo.
- [x] Build exact fixture VMFs and VBSP; inspect generated instances in Hammer.
- [x] Visibility preflight passes after structural changes.
- [x] Human reviews one isolated enlarged land cell and coast case before broad
  preview rollout. Stop for corrective authoring if joins/height/seals are wrong.

### Phase A implementation evidence (accepted 2026-10-06)

- Both enlarged land/coast **in-game geometry reviews are user-accepted**.
  User approved Sandbox for isolation from survivor/loot services. Only the two
  accepted land/coast fixture maps completed VVIS/VRAD (0 failed/incomplete);
  hash-verified temporary copies were placed in engine `maps`, then removed
  after return. Coast startup used Steam with explicit `+gamemode sandbox`
  and the exact fixture `+map`; no cheat changes. Return confirmed through
  a fresh bridge request at `zn_preview_start`/preview after the user unpaused.
  City/preview survivor persistence report sections are byte-equivalent to
  the pre-review JSON serialization; world bounds suite passes 6/6 again.
  This does not validate integrated pursuit, loot lifecycle, skyline or gates.
  User explicitly accepted Phase A and authorized Phase B, carrying integrated
  pursuit/loot/gate checks into their planned later phases.
- User accepted both exact land/coast Hammer fixtures after the agent opened
  them in Hammer++ on 2026-10-06. The user closed the editor windows after
  review; their disappearance was not a confirmed crash. When the user selects
  fixture inspection, agents must open the exact VMFs rather than merely list
  paths. Enlarged-cell in-game visual review remains a separate gate.
- User confirmed the canonical straight faces north and the corner opens
  north/west. Instance-only inward rotations are implemented; source brush
  geometry, overhangs, army offsets and editor backups are preserved.
- Shared bounds owner: `bin/cell_bounds.psm1`. Outer placement/shell owner:
  `bin/outer_edges.psm1`. Settings remain **disabled** for normal city/preview
  builds; `bin/test_outer_edges.ps1` writes isolated enabled settings under
  `generated/outer_edges`.
- Expanded recipes have a `-edge2` suffix; core placement selection happens
  before this suffix. Fixture recipe count remains 18; full preview planning
  remains **179**, so this implementation introduces no combinatorial count
  increase. Production inventory/bytes are not yet measured.
- Builder-generated `.layout.json` files preserve core and border placements,
  outer placements, coast sides, bounds and VMF SHA256. Runtime export rejects
  missing/stale expanded layouts. Shared GLua validates bounds/coast metadata
  and provides legacy-compatible APIs; foliage/bodies retain core bounds,
  Walker placement excludes border/sky-room nav candidates without cutting
  pursuit navigation, and enlarged-city prop-loot discovery excludes border
  props without changing legacy/den eligibility.
- **Static:** outer edges **519 assertions passed**; GLua **184 checked/0
  failed**; existing border showcase (36 cells/seven topologies) and safe-zone
  entrance suite (11 placements, 12 orientation/water and two rejection
  fixtures) pass. Core/frontage emission is reused unchanged; no frontage or
  multi-tile assignment edits. Isolated tile zoos rebuilt, including `zoos/zoo_edges.vmf`.
- **Structural:** ten exact fixtures pass VBSP, no failed/incomplete stages.
  Four land/coast/carpark fixtures pass portal budgets (maximum 511 clusters/
  1608 portals); six entrance/bridge/radioactive/fortified/military fixtures
  pass (maximum 433/1422). Limits remain 1500/2700; no invalid/missing PRTs.
- VBSP exposed incompatible static tree/sign models in the new tagged assets.
  User approved fixed dynamic props. Only 15 classname values across
  `tile_edge_army_none.vmf`, `tile_edge_ra_none.vmf`,
  `tile_edge_ra_wall_1a.vmf` and `tile_edge_ra_wall_1aa.vmf` changed; exact
  comparison to the retained Phase 0 originals confirms all other source
  bytes unchanged. Incremental recompilation rebuilt four affected coverage
  fixtures and skipped the other two. `test_outer_edge_bsps.ps1` verifies
  **287** corrected dynamic instances retained at exact transformed positions.
  Old border/core prop warnings and mounted sky-flag warnings remain separate,
  pre-existing compiler limits; they are not hidden or claimed fixed.
- **In-engine fixture:** fresh `changelevel zn_preview_start` followed by
  `zn_test_world_bounds` passes **6/6** with separate preview-launcher state
  confirmation. This is isolated GLua operation evidence, not enlarged-map
  pursuit, loot persistence, collision or visual acceptance. No character,
  inventory/equipment or loot reset occurred.
- The authored transition roads still have their old core-side clip and the
  generated barricades/gate centres remain at 1568. Inspected and retained for
  the planned Phase C migration; do not stage a partially migrated travel system.
- **Phase accepted:** both Hammer and isolated Sandbox geometry reviews are accepted;
  proceed with Phase B. Gameplay exclusions/access clips
  have static/API/geometry evidence; integrated gameplay remains a retained
  validation limit for later integration. No broad preview regeneration, skyline rebuild, promotion,
  production rebuild or Workshop upload has been performed.

Reproducible structural fixture commands (after `test_outer_edges.ps1`):

```powershell
$maps = @(Get-Content .\generated\outer_edges\compile-required.txt)
.\bin\compile_cell_vmfs.ps1 -WorldProfile preview -SettingsPath .\generated\outer_edges\settings.json -SourceDirectory .\generated\outer_edges\src -BuildDirectory .\generated\outer_edges\build -MapFilename $maps -VBSPOnly -MaxParallelProcesses 2
.\bin\check_vis_budgets.ps1 -WorldProfile preview -SettingsPath .\generated\outer_edges\settings.json -RequiredCellList .\generated\outer_edges\compile-required.txt -PlanData .\generated\outer_edges\plan.json -CellDirectory .\generated\outer_edges\src -BuildDirectory .\generated\outer_edges\build -ReportPath .\generated\outer_edges\build\vis-budget-report.json -RefreshPortalData
$maps = @(Get-Content .\generated\outer_edges\coverage-required.txt)
.\bin\compile_cell_vmfs.ps1 -WorldProfile preview -SettingsPath .\generated\outer_edges\settings.json -SourceDirectory .\generated\outer_edges\coverage -BuildDirectory .\generated\outer_edges\coverage-build -MapFilename $maps -VBSPOnly -MaxParallelProcesses 2
.\bin\check_vis_budgets.ps1 -WorldProfile preview -SettingsPath .\generated\outer_edges\settings.json -RequiredCellList .\generated\outer_edges\coverage-required.txt -PlanData .\generated\outer_edges\coverage-plan.json -CellDirectory .\generated\outer_edges\coverage -BuildDirectory .\generated\outer_edges\coverage-build -ReportPath .\generated\outer_edges\coverage-build\vis-budget-report.json -RefreshPortalData
.\bin\test_outer_edge_bsps.ps1
```

Review sources: land `generated/outer_edges/src/zz_preview_d4cbfaa03e4b-v1-edge2.vmf`;
coast `generated/outer_edges/src/zz_preview_d4cbfaa03e4b-wtrnw-edge2.vmf`;
all nine canonical sources in `generated/outer_edges/zoos/zoo_edges.vmf`.
Coverage VMFs and matching layouts are under `generated/outer_edges/coverage`.

## Phase B - Skyline models, 5760 pitch and unchanged coast attachment

**Objective:** actual regenerated skyline matches new geometry without overlaps,
missing water or pushing the ocean backwards.

Implementation notes:

- Update sky-room/model-builder pitch and client neighbour/tower placement together.
  Current pitch includes the old border (4480); core HUD bounds are a separate
  3200 contract. Rebuild relevant model inputs from current recipe VMFs.
- Audit model bounds, detail props/wrecks, snow overlays, tower-only extraction,
  lighting sample rings, horizon/cloud extents, edge terrain and fog distances.
  Wider spacing is not authorization to raise draw/population budgets.
- Ensure selected/current recipe extraction includes edge instances/materials;
  dependency hashing includes recursive source changes and footprint settings.
- Emit side-specific coast attachment data. Coast on an omitted side stays at
  the existing border's physical edge (2240 from the original centre), even
  though neighbouring cell centres are now 5760 apart.
- Fill resulting water space with water, not a terrain strip or relocated seam.
  Preserve waterline height, foam/wall treatment, existing piers/tips and current
  cell-relative alignment. Route corridors do not relocate the whole shoreline.
  On 2026-10-06 the user explicitly chose to retain the existing 640-unit-wide
  procedural beach beyond the 2240 border. Keep that original beach shape;
  fill only the remaining space with water, rather than removing the beach.
- Test detailed neighbour grid and distant tower coordinates, not only current
  cell rendering. Keep physical north (+Y) distinct from tile Y increasing south.
- Version incompatible manifests/caches; update consumers/packaging validation
  coherently. Reject stale mismatched assets explicitly.
- Run structural visibility checks before full preview compilation. Preview only;
  city production assets remain gated until Phase I.

Checks / acceptance:

- [x] Skyline manifest/tower/height regressions and new pitch/coast seam assertions.
- [ ] No intersecting duplicate cell models, disconnected route visuals, old snow
  overlays, missing materials or changed source/core positions.
- [ ] Four coast orientations and mixed corners at unchanged border attachment.
- [ ] Fresh client review: enlarged dense city, land-to-neighbour joins, ocean,
  bridge corridor, snow/weather seam and distant tower visibility.
- [ ] Matched before/after samples record actual model/triangle/draw/memory counts
  and frame scope; hook timings alone are not a performance verdict.

### Phase B implementation evidence (2026-10-06; not accepted)

**2026-10-07 coast correction supersedes the omission-policy evidence below:**
the requested coast is the Storm Drain at grid `(0,12)`, logical `(0,0)`,
not the isolated SE authored water-corner fixture previously opened. User
explicitly chose omission **only** at the west 3D-skybox ocean boundary.
`skyboxOceanSides` now identifies that boundary separately; `waterBorderSides`
continues selecting all original border tiles without alteration. West recipes
carry `-oceanw-edge2` identity so they cannot share inland outer geometry.
Installed legacy policy remains 179 recipes; the corrected isolated expanded
preview now has 187 (approved variant growth, not changed core assignments).
Storm Drain retains its 21 original border pieces and all core/entrance
placements, with 23 new outer placements and zero west outer placements.
Its renderer coastline remains at **-2240**, not -2880; a 640-unit band connects
the border to the west skybox ocean and preserves the original beach.
Current skyline fixture checks pass **275 assertions / eight recipes**;
outer-edge checks pass **1158 assertions**, including exact legacy Storm Drain
source-instance transforms. Original border showcase and safe-zone entrance
regressions pass unchanged.
eight portal fixtures pass with maximum **474 clusters / 1517 portals**.
The new exact west-border/no-gap GLua case is syntax-checked but not yet run:
Garry's Mod is closed. Fresh visual review remains unverified. No maps,
runtime exports, models or authored templates were installed/changed by this
correction. Earlier cardinal/mixed tests exercise general geometry logic,
not permission to omit east/north/south outer scenery.

- Sky-room coverage and model/client neighbour spacing use shared bounds:
  5760 expanded pitch, 4480 legacy. Tower, detail/wreck, horizon/cloud and edge
  terrain placements retain their existing radius/population/draw limits.
- Expanded skyline schema 2 records exact plan identity, bounds and generated
  per-recipe coast sides/VMF hashes. Client and packaging reject mixed
  legacy/expanded footprints, stale plans and coast mismatches. Installed
  schema-1 content remains supported and unchanged.
- Builder follows the plan's actual source directory, supports isolated model
  intermediates with `-BuildDirectory`, and recursively hashes VMF dependencies.
  Base/snow/tower cache versions changed together; all three required model
  companions must exist and be nonempty for reuse.
- Client coast uses side-specific rectangles and non-overlapping omitted bands;
  wall and retained beach attach at 2240 on omitted sides. Shared sample cuts
  across full slots/bands prevent mixed-corner T-junctions. Fog continuity stays
  at the old border; lighting sample limits stay within the old traversal
  envelope. No sea level, beach width, foam/material or weather policy changes.
- Focused skyline regression: **177 assertions**, six isolated land/coast/tip/
  bridge/tower recipes, actual edge transforms and source/snow/tower extraction.
  Tests prove recursive invalidation, unchanged-cache reuse and recovery from
  a missing VVD. Compiled outputs: seven base parts / 62792 triangles, six snow
  parts / 10342 triangles; 559 detail candidates include 41 generated wrecks
  from 33 mounted models and 378 fire candidates. These are fixture catalogue
  totals, not simultaneous live draws or performance measurements.
- Expanded manifest passes exact recipe/layout/companions/settings checks.
  Installed legacy manifest also passes: 179 recipes, 28 tower cells, all 576
  viewpoints, worst distant parts 28 against the unchanged 128 cap.
- Tower extraction and skyscraper-height regressions pass; outer-edge suite
  still passes 519 assertions. GLua **186/0**. Fresh server geometry suite
  **8/8** covers every cardinal/mixed mask, three neighbour offsets, fog,
  stale compatibility, legacy sample coordinates and actual shared mesh cuts.
  This is isolated geometry logic, not a client-renderer appearance check.
- Packaging fixtures **57/57** include matching expanded preview beside legacy
  city and rejection of old skyline, stale plan and wrong coast attachment.
- Six isolated VBSP/portal checks pass: no failed/incomplete stages, no invalid
  PRTs, maximum **417 clusters / 1317 portals** against 1500/2700. Fixed the
  visibility runner to forward its explicit source directory to the compiler;
  its first isolated invocation incorrectly fell back to normal profile sources
  and stopped at the sibling-directory guard before compiling.
- Sources/models/reports are under `generated/skybox_edges`; normal outer-edge
  settings remain disabled. No new BSPs/models/runtime exports are installed,
  no VVIS/VRAD/full preview rollout/publication, no character or loot changes.
  The existing preview launcher was reloaded only for the isolated logic suite.
- **Next gate:** fresh matching client review of dense/land/coast/bridge/
  snow/weather/tower visuals and matched workload measurements, with a retained
  restoration path before temporary staging. Four-side/mixed-corner logic is
  verified; expanded renderer appearance and model joins are not yet accepted.
- User chose immediate Hammer inspection; opened the exact new SE coast
  `zz_preview_c253a543e5cb-wtres-edge2.vmf` and skyscraper
  `zz_preview_33450952e2af-edge2.vmf` from `generated/skybox_edges/src` in
  separate Hammer++ launches. Opening is not human or phase acceptance.

## Phase C - Gate relocation, arrival consistency and road-arrow rendering

Implementation notes:

- Derive the border/edge boundary from bounds metadata, not duplicated constants.
  For the centred fixture, N/E/S/W boundary planes are +/-2240.
- Existing gate centres are hardcoded +/-1568, 32 units inside the old core edge.
  Preserve that inset when relocating: expected centres +/-2208, while retaining
  trigger thickness/height and eligible route definitions. Verify full trigger,
  prompt range, barrier geometry and departure walk against the boundary.
- Trace pending-entry producer and consumer, map-generated landmarks/anchors and
  destination safe placement. Relocate the corresponding arrival, not just the
  outgoing trigger. Keep the existing arrival/departure timing/forced movement.
- Server publishes trigger centres through `Global2` because trigger entities are
  not networked. Extend authoritative marker data only as needed (direction,
  surface anchor/height/state); do not rely on client `ents.FindByClass` finding
  server-only triggers or add one permanent marker entity per client.
- Reuse waypoint/blocked state owners. Arrow rendering is bounded/static geometry;
  cardinal vector determines orientation, not camera-facing billboard rotation.
- Verify terrain/ramp surface with a bounded ground trace and lift along normal.
  Guard material availability and skip unsupported/no-surface cases with explicit
  diagnostics. Do not draw sky/ground-through-bridge success-shaped fallbacks.
- Use depth/capture-pass discipline. Ground arrows are not baked atlas artwork;
  map markers use their own projected authoritative anchors. Avoid duplicate
  arrows in captures and destroy replaced meshes on reload/cleanup.
- Keep E range, single-human restriction, eligibility, waypoint logic and current
  prompt colours. Fix stale published marker counts after clean load, not from
  service-test reinitialization alone.

Checks / acceptance:

- [ ] Static four-direction positions/angles and exact 192x128 marker dimensions.
- [ ] Live normal/yellow/blocked-red, 1280 range, road occlusion, bridge height.
- [ ] Live N/E/S/W travel, arrival facing/walk, saved logical coordinates, same-BSP
  neighbour travel and den entrance/exit regressions.
- [ ] Reload independently after destructive fixture/service tests before judging
  normal marker counts. Read-only status confirms actual destination.
- [ ] Human approves readability and gate distance; no movement into blocked edge.

## Phase D - Full-footprint minimap, world artwork and satellite capture

Implementation notes:

- Render new placement metadata into cell artwork at a common 9-tile frame.
  Preserve logical world tiling/click targeting while adjusting the core's inset
  within each texture. Coast sides use the omitted-space water treatment.
- Update satellite stitching and staged/wireframe variants together, including
  launcher Tools map-atlas consumers. Do not append decorative pixels without
  updating texture-to-world transforms.
- Remove inappropriate HUD `1600` assumptions for visual projection, not gameplay
  coordinates. Use captured/generated centre and span for player/spot/door/gate
  markers; test cardinal signs and core/border/outer reference points.
- Current level capture span is derived independently from camera/FOV. Set city
  capture to the authoritative visual footprint and keep camera below the separate
  sky-room ceiling. Preserve existing flat ortho-key usage verified for GMod.
- Maintain den span rules independently; do not multiply den coverage by an
  enlarged city span accidentally.
- Bump capture/artwork cache versions and include profile, map/recipe, extent and
  content revision. Same BSP in different logical cells must not confuse dynamic
  markers; persistent captures must not mask new geometry.
- Preserve minimap zoom/modes, live-map movement, world click/waypoint semantics,
  player/entity capture hiding and restored render state on failure.

Checks / acceptance:

- [ ] Automated projection tests for centre, +/-1600, +/-2240 and +/-2880,
  all four directions and asymmetric coast omissions.
- [ ] Fixtures prove artwork consumes actual edge/environment/route placements.
- [ ] Fresh staged images, wireframes and stitched satellite belong to same plan.
- [ ] Human sees full borders/edges on minimap/world previews/level capture.
  Player/loot/doors/gates remain aligned and den capture is unchanged.

## Phase E - Slower movement and rarer, spaced searchable loot

Implementation notes:

- Set movement scales to 0.675/0.765 in the owning server module; do not multiply
  already scaled engine speeds on every refresh or spawn.
- Update exact old/current/new test expectations and GDD/README semantics in the
  same phase. Do not change stamina constants or scripted transition speeds.
- Scope activation scaling to searchable cell generation; do not halve the shared
  loot engine globally if other callers must retain their probabilities.
- Apply `originalChance * 0.5` exactly once. Report expected candidate probability
  separately from final selected density, since spacing suppresses nearby winners.
- Set fallen-body placement to 1-2 while preserving deterministic keys/models,
  settling and profile/cell scoping. Eligibility remains core-only.
- Coordinate body-layout policy with the loot generation's policy version.
  Bodies currently regenerate their deterministic physical plan on map load,
  independently of saved spot rows: simply changing MinCount/MaxCount would
  orphan older body spot keys before loot naturally refreshes. For unrebuilt
  cells with legacy loot, recreate the legacy body plan until that generation
  expires; new/refreshed/reset generations use the new 1-2 plan. Select the
  policy before spawning/candidate enumeration, not after discarding old rows.
- Sort candidates by stable keys before RNG/selection. Give rolled winners a
  deterministic seeded priority, then accept spaced candidates in priority order.
  Do not let `ents.GetAll` enumeration order or an early database row bias one end
  of the map. Use injected RNG/helpers consistent with existing tests.
- Compare actual prop/body search centres with squared 3D distance; accept equality
  at 320. Include cross-type separation. Trace/settling must not invalidate the
  approved measurement: record and verify the stable centre used for a body.
- Save the final selected set through existing atomic cell replacement. Build
  failure cannot silently mark the cell regenerated or partially replace rows.
- Load existing persisted states unchanged until the usual absence regeneration.
  Preserve declined offers, searched spots, outstanding ownership and refresh
  timestamp behavior. Never reroll on every map reload or player arrival.
- Exception: rebuilt-map loot reset is user-authorized once per changed map
  revision. MapCreationID-backed keys are not guaranteed stable after adding
  authored instances/entities, even if core tile assignments are unchanged.
  Implement a verified logical backup and transactional, profile/cell-scoped
  reset tracked by old/new map fingerprints. Resolve every affected logical cell
  sharing that recipe; do not reset city merely because preview was built.
  A repeated load of the same rebuilt revision must not reset again.
- Run reset only at a safe generation boundary before offers/search become live.
  Backup/write failure aborts the reset with explicit errors. Restoration must
  use the matching old map and loot backup together, not old spot IDs on a new BSP.
  Existing inventory/equipment/character/profession/economy tables are excluded.
- Do not apply spacing to enemy drops/player drops via `RegisterRuntimeSpot`.
  Bodies that are inactive can remain scenery; the contract spaces **active
  searchable spots**, not every authored physical prop.

Checks / acceptance:

- [ ] `zn_test_movement`: exact ratios, repeat refresh, spawn, bonuses, exhaustion,
  stationary sprint, sustained/interrupted sprint and unchanged rates.
- [ ] `zn_test_loot` / `zn_test_loot_spots`: original probability halved once,
  deterministic order independence, 319.999 rejection/320 acceptance, separate
  floors, prop-body pairs, core bounds and rollback/error behavior.
- [ ] Existing saved cluster/declined/searched rows remain untouched on upgrade;
  absence threshold boundary causes one normal spaced regeneration.
- [ ] Unrebuilt legacy body plans survive reload until refresh. Rebuilt-map reset
  backs up all affected loot, runs exactly once, preserves unrelated profile/cell
  rows and all character tables, and rolls back cleanly on backup/SQL failure.
- [ ] Body count 1-2 in suitable fixtures; physically unsuitable attempts report
  their shortfall rather than faking successful placement.
- [ ] Unchanged enemy/boss/harvest outputs and item quality/counts asserted.
- [ ] Live city-cell walk/sprint and searching tested in actual context, not den
  stubs; persistence reload demonstrated without modifying user cheats/inventory.

## Phase F - Read-only slot previews and bounded thumbnail cache

Implementation notes:

- Current `Characters:List` selects limited model/skin/origin/level fields and
  strips internal character IDs. Extend through the owning character service,
  deriving owner/profile on server; never accept arbitrary character ID/profile
  from the client.
- Query saved bodygroups/player colour, player data (resume coordinates/safe-zone),
  inventory worn selections and selected equipment using existing SQL helpers.
  `ZM_GetPlayerData`, `ZM_GetPlayerItems`, `ZM_GetEquippedWeaponSlots` are starting
  points; validate their real contracts before use.
- Return only presentation data for the requesting owner's three profile slots.
  Do not call `Characters:Select`, `LoadSelectedCharacter`, inventory load/sync or
  equip operations merely to assemble a card. Separate existing legacy-name
  migration from the new read-only snapshot contract.
- Distinguish saved resume, original origin and undefined/undeployed start. Resolve
  den ownership through `ZM_SafeZones`/`ZM_World`; do not infer map coordinates from
  a BSP filename or clamp all survivors to the origin's +/-1-cell area.
- Missing valid start uses the defined new-character start; corrupt/missing saved
  resume data produces explicit diagnostics and a disabled unavailable preview.
  Never silently show a different destination as if it were the saved one.
- Include a presentation revision derived from actual appearance/equipment/resume
  fields. Card cache keys include profile/slot plus that revision and renderer
  version; internal ownership need not be exposed.
- Build full-body thumbnails on isolated client entities in a budgeted queue,
  using existing clothing composition/weapon visual helpers. Compose during a
  safe PreRender phase, not nested material builds in panel Paint.
- Keep the existing clothing pool capacity and pin semantics. Wait/retry explicit
  transient failures; never permanently cache naked fallback as a successful outfit.
  Release pins and preview entities on page exit/revision/cleanup.
- Cache at most the visible three profile slot cards plus an in-flight build,
  not every historical outfit. Bound/reuse render targets; avoid unique RT names
  on every reopen because engine RT resources cannot be reclaimed like Lua tables.
- Active weapon visual is a read-only model/skin snapshot. Do not create a real
  weapon entity, grant ammunition or run SWEP deployment/animation gameplay.
- New appearance-required cards label that state and keep Deploy disabled.

Checks / acceptance:

- [ ] `zn_test_characters`/inventory-focused assertions verify owner/profile/slot
  isolation, correct saved equipment/location and no database/active-slot mutation.
- [ ] Snapshot collection twice is idempotent; same player/profile state and
  inventory/equipment hashes remain unchanged.
- [ ] Client card cache invalidation, cancellation, queue budgets, failed build
  retries and resource/pin cleanup tests.
- [ ] Human compares all occupied cards to actual saved outfits/active weapons,
  including distinct slots, empty/legacy states and saved den locations.

## Phase G - Distressed Earth and bounded fictional city renderer

**Prototype gate first:** clear exact assets, build one Earth and one selected-cell
city example, then obtain appearance/performance approval before broad polish.

Implementation notes:

- Retain existing launcher camera/globe anchors and accepted sky-inspection/credits
  scenes. Implement a presentation owner that can switch Earth/city/hidden states,
  not another always-active competing render hook.
- Replace current per-frame globe grid/vector/quads allocation with reusable static
  sphere geometry and transforms. Validate UV seam/poles/winding and nonzero mesh
  counts. No frame-by-frame sphere rebuild.
- Use documented shaders/material composition for day/night/light/cloud/rim layers;
  prove exact shader capabilities in a small GMod prototype. Do not claim a stock
  shader supports a custom lighting blend without evidence.
- Original distress overlays can modulate approved textures; atmospheric smoke is
  bounded cosmetic presentation, not world weather/particles emitted into gameplay.
- Define high/low quality from measured mesh/material/layer costs. Preserve current
  saved `zombiesim_globe_quality` choices and integrate its help/reset/preset behavior
  without changing unrelated options. New/reset default is high.
- Package each approved texture/material/licence exactly once in Common Content.
  Keep source art outside distributable outputs; build/stage with documented
  ownership. Log source resolution, compressed/GPU texture estimates and mipmaps.
- City scene uses selected profile's skyline manifest/models and correct logical
  coordinates. Draw selected cell plus bounded relevant neighbours/towers, not
  the entire world. Use deterministic nearest-first budgets, no new cap expansion.
- Reuse model content, not the live skybox singleton's mutable current-cell state.
  Do not call gameplay `Skybox:Refresh` with a fake player cell to aim a menu.
- Represent selection/resume/den with explicit marker/label. Camera maps the full
  logical cell coordinate to city-local pitch; keep real Earth anchor distinct
  from fictional city-grid offsets.
- Smooth Earth-to-region motion can hand off via a bounded visual blend to the
  stylised city. Do not promise literal planet geometry resolving into BSP streets.
  Human prototype approval settles framing/art, not a guessed seamless effect.
- Missing/stale skyline assets show an explicit unavailable status; Deploy remains
  governed by existing content checks. No random/generic city or hidden production
  rebuild. City-profile appearance acceptance remains blocked until assets exist.
- Render only the visible owner. Avoid the previous double-full-scene
  `RenderView` pattern; preserve the accepted sky-flight RenderScene replacement.
  Skip capture/depth/skybox passes as appropriate and restore all render state.

Checks / acceptance:

- [ ] Cold-load material validity/dimensions, sphere seam/poles, quality modes,
  day/night/cloud/rim layering and bounded model/resource counts.
- [ ] Scene data tests: current saved cell, den owner, undeployed start, distant
  logical cells, profile switching and explicit missing/stale assets.
- [ ] Human prototype approves post-apocalyptic Earth/city at normal launcher view,
  close zoom and low quality; logo cannot be substituted during this review.
- [ ] Matched home/city warm samples target 60 FPS; record full-frame FPS and
  median/p95/p99 frame time, hook CPU, draws, textures/memory and cold build spikes.
  If target fails, optimize/review trade-offs before calling this accepted.
- [ ] Repeated scene switches/reopens plateau resource counts. Gameplay/credits/
  sky tour are not rendered twice or left with changed lighting/fog/material state.

## Phase H - Home/Play flow, cinematic camera, Tools, Settings and logo

Implement explicit states rather than scattered page booleans:

| State | Left side | Right side / ownership |
| --- | --- | --- |
| Home | Play, Tools, Settings, Exit; supplied logo | Earth, bounded manual controls |
| Entering Play | Character cards usable immediately | 3-second Earth-to-city transition |
| Play | Three-slot grid, selection actions, Back | Selected saved location, 1-second retarget |
| Create / Set Appearance | Existing wizard | Existing full-body creation preview replaces city |
| Settings | Existing options + Credits + Content Addons | Earth unless a dedicated child tool owns the view |
| Tools | Read-only entries; disabled preview-only actions in city | Existing right-side workspaces/child tool ownership |
| Credits | Existing credits flow | Existing credits camera; Earth/city suspended |
| Sky inspection | Existing browser/temporary inspection flow | Existing flight/tour/fog/music/fades; Earth/city suspended |
| Returning Home | Home controls usable | 2-second city-to-Earth return |
| Deploying | Existing waiting/content-gated state | Existing deployment/loading owner |

Implementation notes:

- Home opens before any normal automatic deployment. Preserve explicit developer
  autoload as a developer override; disable it only with user approval for tests
  and restore it afterwards. Do not delete debugging behavior.
- Last-active selection is a UI default, not a call to server selection.
  One click highlights/pans; Deploy alone sends the existing select request.
- Create/deletion completion returns to the grid coherently. Preserve typed-name
  confirmation, request timeout, duplicate-request prevention and error visibility.
- Implement responsive wrapping card layout for the fixed three slots, keyboard
  focus/selection and scroll handling. Keep cards readable at supported resolutions.
  Do not leave old Deploy-per-row buttons alongside the new selection contract.
- Interruptible camera transitions interpolate from current pose. Back, selection,
  create, resize, credits, sky inspection and close cancel/retarget deterministically.
  No timers should resurrect removed scenes or stale selections.
- Manual drag capture belongs only to exposed Home Earth viewport. Release it on
  mouse-up, lost button, Back, focus loss, page switch, Escape and parent removal.
  Wheel over a scroll panel must remain panel scrolling.
- Add contextual Reset View; do not save user drag as a new gameplay location.
  Clamp zoom using measured sphere/camera bounds, never allow camera through Earth.
- Move Settings entries without removing current precise controls/convars/server
  guards. Existing Options section persistence, changelog, engine-owned audio and
  sky browser/custom palette persistence remain intact.
- Split Tools visibility from action availability. City can see Tools and
  non-preview capabilities; preview-only actions are disabled with a reason.
  Audit hardcoded preview atlas paths before allowing any city atlas action.
- Preserve existing tool right-side composition, Back/Escape cleanup and content
  subscription/download/mount distinctions. Missing packages remain deploy blockers.
- Integrate supplied logo with its aspect ratio/transparency, grunge framing and
  slow breathing effect. Readability/hit targets must not depend on distress noise.
- Exit remains a confirmed disconnect to GMod, not application termination.
- Do not alter accepted sky-flight timing/music/end-blackout or authored launcher
  alignment. Map rebuild is unnecessary for Lua/texture changes unless actual
  authored scene geometry must change and the user approves that change.

Checks / acceptance:

- [ ] Fresh-load Home has exactly four primary actions; Play/selection never
  deploys before explicit confirmation.
- [ ] Create, legacy appearance, typed delete/cancel, empty/no-slot, failed request,
  content failure, Exit cancel/confirm and return-to-grid tested.
- [ ] Exact camera durations/rapid retarget/Back/resize/cancel ownership tests.
- [ ] Manual controls/Reset View work only on Home; every cleanup path restores
  mouse/camera correctly, including tool/browser/credits/appearance round trips.
- [ ] Both-profile Settings/Tools availability and unchanged admin/profile guards.
- [ ] Human approves actual new supplied logo, distressed menu, cards and camera
  choreography; static tests are not visual acceptance.

## Phase I - Integrated acceptance and separately approved city rollout

- [ ] All phase static failures fixed and human acceptance recorded individually.
- [ ] Build/stage the complete matching preview closure only after fixture gates:
  current recipes, BSPs, required preview nav data, skyline models/materials,
  artwork/satellite and runtime exports. Audit failed/incomplete compiler stages.
- [ ] Fresh preview load: traverse enlarged border, pursue a walker onto reachable
  border road, verify no border spawning/search/harvest, four gates/arrivals,
  coast alignment, map overlays, rarity persistence and ordinary movement.
- [ ] Fresh launcher: Home -> Play -> multiple cards -> Back -> Settings -> Tools ->
  sky tour -> return -> Create/appearance cancel -> explicit Deploy.
  Preserve user selection/preferences/inventory throughout read-only checks.
- [ ] Matched performance checks include Earth, city with populated cards,
  transition/reopen cold spikes and gameplay enlarged skyline workload.
  Do not compare unmatched populations/weather/cameras or call hook CPU a GPU test.
- [ ] Run packaging fixtures/read-only audit for new owned content and compatibility,
  without upload, unowned-file deletion or release-status promotion.
- [ ] Present preview evidence and request **separate city rebuild approval**.
  If not granted, record city rollout explicitly deferred/unaccepted; do not call
  both-profile world acceptance complete.
- [ ] If approved, rebuild only current required production closure from matching
  city inputs; do not reuse preview exports. Validate city skyline, nav/travel,
  artwork, launcher slot/profile isolation and content compatibility separately.
- [ ] User accepts integrated result. Archive tracker/re-root links and update
  AGENTS/README/version/changelog together. Development complete is not released.
- [ ] Restore/verify all owned test substitutions and user preferences. If final
  instrumented restoration is unavailable, record human confirmation separately.

## 5. Command and validation guidance for the implementing agent

Do not run the following merely to prepare this plan. Use the narrow phase checks
first; these are implementation-time workflows, not completed evidence.

### Static Lua and live suites

After every Lua batch:

```powershell
.\bin\test_glua_syntax.ps1
```

Use the relevant existing in-game suite (`zn_test_characters`, `zn_test_movement`,
`zn_test_loot`, `zn_test_loot_spots`, `zn_test_inventory`) and add focused cases
through `ZM_TestHarness`. Fixtures must implement real-path methods; preserve
approved exceptions. Discover actual transition/skybox/browser suite names from
their registrations/README rather than inventing console commands.

Bridge commands go through:

```powershell
.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_player_status'
```

Never use `lua_*`/`lua_refresh` via bridge. For new code, confirm profile/map then
use supported `changelevel`; acknowledgements do not prove asynchronous client
completion. Exit 2 means stale heartbeat: ask the player, do not loop. Launcher
arrival is not deployment; deploy explicitly before gameplay tests.

### Preview pipeline after fixture regressions

For settings/planning changes, follow the matching preview workflow:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -WorldProfile preview -RequiredCellList .\bin\preview_grid_24x24_seed_1337_required_cell_vmfs.txt
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
.\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
```

Resolve exact configured inputs rather than assuming those example filenames are
current. Identify affected recipes before compiling. Preserve incremental
dependency detection; no routine `-Force`/`-ForcePortalData`.

Build skybox models from refreshed matching recipe inputs; inspect model-builder
parameters before narrowing outputs. Regenerate map artwork and runtime data via
supported pipeline scripts, never manual JSON/PNG/VMF edits.

Only after portal/structural checks and when playable output is needed:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -PrioritizePortalCost -CleanStagedCity
```

Skip-VBSP is valid only if source/dependency VMFs have not changed since preflight.
Inspect compile reports; failed/incomplete stages block staging/acceptance.

### Related focused offline checks

- [Border showcase](bin/test_border_showcase.ps1)
- [Safe-zone entrances](bin/test_safezone_entrances.ps1)
- [Building frontage](bin/test_building_frontage.ps1) and
  [multi-tile templates](bin/test_multi_tile_templates.ps1) when affected
- [Skybox manifest](bin/test_skybox_manifest.ps1),
  [towers](bin/test_skybox_towers.ps1) and
  [skyscraper height](bin/test_skyscraper_height.ps1) when affected
- [Map naming](bin/test_map_naming.ps1) when recipe identity changes
- [Launcher parity](bin/test_launcher_parity.ps1) only when authored launchers change;
  their intentionally different scenes must not be forced identical
- [Workshop fixtures](bin/test_workshop_packages.ps1) for asset/compatibility changes

Add a focused outer-edge/extent/projection fixture where no existing test covers
the exact requirement. Do not add unrelated tooling or run every historical suite.

## 6. Handoff, blockers and reporting

### Required external inputs / explicit stop conditions

1. **Implementation go-ahead:** granted on 2026-10-06; Phase 0 is active.
2. **New logo artwork:** user-supplied, blocks final H art acceptance.
3. **Exact globe asset clearance:** agent investigates allowed providers, records
   provenance and rejects unclear rights before staging.
4. **Authored joins:** inspect actual north-facing source/corner geometry. If a
   protected source conflict requires user asset changes, show the failing fixture
   and ask; never solve it with unrelated shared rotations.
5. **Earth/city prototype review:** user judges art/framing before broad polish.
6. **Production rebuild approval/assets:** missing city skyline remains explicit;
   separate approval needed for Phase I production output work.
7. **Performance target failure:** report measured scope and proposed trade-off;
   do not quietly lower approved quality or increase existing resource budgets.

These are named approval/evidence gates, not unspecified features for an agent to
guess. No harbour expansion, new character capacity or publication is implied.

### Checkpoint at each subsystem boundary or failed loop

Record phase, approved contract, exact profile/recipe/map/logical cell, source
changes, test command/results, human feedback, restoration state and the next
discriminating check. Keep checkpoints in session storage unless the user requests
a repository document. Do not accumulate ambiguous "looks fine" completion notes.

### Acceptance ledger

| Phase | Implementation | Static/automated evidence | Live/human acceptance |
| --- | --- | --- | --- |
| 0 | Complete | Source/fixture/backup evidence above | Accepted 2026-10-06; coast/gate/quality/cold-warm limits explicitly carried to A/B/G |
| A | Not started | Not run | Not run |
| B | Not started | Not run | Not run |
| C | Not started | Not run | Not run |
| D | Not started | Not run | Not run |
| E | Not started | Not run | Not run |
| F | Not started | Not run | Not run |
| G | Not started | Not run | Not run |
| H | Not started | Not run | Not run |
| I | Not started | Not run | Not run |

Always report implementation, tests, visual acceptance and explicit deferrals
separately. Do not re-open accepted Alpha 3.1.0 work to make this ledger look fuller.