# Developer Changelog

Internal engineering history for ZombieSim. The player-facing changelog is maintained in [changelog.json](../content/data_static/changelog.json).

## 2026-10-17 - Player and developer documentation split

- Preserved the previous detailed changelog in this file before rewriting the in-game changelog as short player-facing feature notes.
- Removed development phases, test evidence, staging records, internal tools, and reconstructed-history flags from the public changelog; versions without player-facing changes are omitted.
- The Alpha 3.2 player entry calls out the new motorway routes, buildings that reflect local density, and gate-travel improvements.
- Replaced the version banner's internal phase summary and removed "in progress" from the public changelog legend.
- Moved the 1,984-line technical README to `docs/readme.md`, rebased its 32 local links, and created a concise player overview at the repository root.
- Updated project guides and historical documentation links to the technical README.
- Validation: player changelog/version data passes JSON and content checks (17 entries); 42 local documentation links resolve; GLua syntax passes 281/0; `git diff --check` passes. The revised in-game legend has not been live-reviewed.

## Current Alpha 3.2 development record (2026-10-17)

### Motorway travel

- Transition availability now follows `ZM_World` neighbor exits; gate geometry is used only for presentation and arrival markers.
- Server transition fixtures pass 12/12 and GLua syntax passes 277/0. Live review confirmed the west and east gates work and motorway alignment is correct.

### Preview map updates

- BSPs `zz_preview_74c1b0c24754` and `zz_preview_a30b0e90c7e2` are staged in both `content/maps` and the engine maps directory, with hashes matching their isolated builds.
- Preview logical cells 454 and 113 resolve to those BSP names. All 336 active preview cell materials and browser thumbnails were refreshed; the old `-edge2` cell images were removed.
- The skyline manifest now contains footprints for the renamed maps. Its model arrays temporarily reuse the replaced recipes; exact per-map skyline models and full revision hashes remain for the later all-map export.

### Cell Health Manager maintenance batch

- The preview-admin grid reports navmesh presence, current-map clear/atmospheric photos, and per-map cubemap confirmation. It does not compare revision hashes.
- The batch is explicitly user-started. The server recomputes selected work and queues the union of cells missing any checked artifact. Navmesh and cubemap jobs deduplicate by BSP; photos remain per logical cell.
- Navmesh generation saves, reloads and validates before photos begin. Photo imports merge valid existing captures for unchanged map names.
- `buildcubemaps` remains manual: the player runs it in the native console, then confirms success after reload. Confirmation is persisted as `USER CONFIRMED`, not engine-verified. A No response leaves the map incomplete and continues the batch.
- Focused checks pass: Cell Health contract 6/6; capture client 7/7 and server 11/11; importer 6 tests; runtime map-name/skyline updater 9 assertions; GLua syntax 281/0. The live client suite passes 7/7, and the controls were reviewed as visible and legible with the skyline warning cleared.
- No maintenance batch has started. Actual navmesh generation, photo capture/import, native cubemap work, and restoration remain unverified.

### CSM and scope

- The current default-off client-local additive CSM implementation is accepted for now; baked/shared lighting remains unchanged. Further CSM validation stays deferred.
- Broad generator and full-map revision work remains paused. Do not start a maintenance batch automatically.

## Historical detailed records

The entries below preserve the implementation notes that were previously stored in the player-visible changelog. They are historical snapshots; the current record above takes precedence where status or wording differs.

### 3.2 - Density-Aware Generator, Wide Motorways and CSM

**Status: in development | Date: 2026-10-13**

Alpha 3.2 remains in development. Live motorway gate/alignment and current CSM checks are accepted. Two corrected BSPs are staged and wired to logical cells 113/454 by a targeted runtime map-name update. The 336 active preview cell materials and map-browser thumbnails are refreshed, with stale -edge2 cell images removed. A read-only preview Cell Health Manager developer panel is implemented; focused tests pass and live UI review is pending. The user paused generator work and set the order to CHM review, then full-map navmeshes/screenshots and Satellite/wireframe outputs; the long carried Phase K/L checklists are deferred.

Development notes:
- `+` Proven plain-ground precision defects repaired with verified backups; infill uses full/half/quarter bases and reusable power-of-two rectangles from4 through512, never polygon, decimal-named or sub-4 patches.
- `+` Phase B accepted after seven bounds-based complete-cell fixtures compiled and received user visual review; exact floor-mouth joins remain clearance-pending, mismatched motorway joins and ordinary-road approaches unsupported.
- `+` Global U4/U8 infill adds rectangular sources for narrow bounds-verified gaps; focused regressions and the refreshed seven-cell compile/portal checks pass, and the user accepted the four affected cells after visual review.
- `+` Phase D density/route-adjacency policy accepted without implying complete live generator acceptance.
- `+` Phase E planner/builder explicit rectangular occupancy aligned within the existing three-tile-per-axis limit; duplicate owner IDs and inconsistent occupied geometry fail explicitly, with focused source fixtures and retained-plan compatibility checks.
- `+` Phase E marked/unmarked frontage validates rotated rectangles; building/landmark reservations and access checks use matching dimensions, with focused source tests preserving existing square candidate order and targets.
- `+` Shared rectangular filename parsing, authored edge-marker validation and zoo/test geometry expectations now agree while retaining legacy square shorthand and the ordinary three-tile-per-axis limit.
- `+` Shared straight motorway builder contract validates exact core/border/outer leases, emitting owners, suppressed slots and approved finite origins before ring replacement; focused source fixtures cover both orientations and corrupt records.
- `+` Straight motorway core/ring instance emission consumes explicit physical XYZ without re-deriving reservation centres; focused entity-output fixtures preserve fractional coordinates and ordinary tile output.
- `+` Normal plain-straight motorway planning reserves its full three-wide core before density decorations using the reviewed stripe geometry; focused tests and two isolated normal recipes pass. Playable emission remains blocked until rings/gates/runtime are integrated.
- `+` Normal straight plans now declare source-fingerprinted core/border/outer leases; boundary replacement preserves unleased walls/corners and wall-density adjacency consumes the same reservations. Isolated normal plan-only workflow verifies both orientations; gates/runtime remain pending.
- `+` Straight normal assembly metadata now derives asymmetric gate lanes, deck heights, arrow and arrival coordinates from current authored floor windings in all four directions; source/grade/boundary checks reject invalid measurements. Brushes/runtime consumers remain pending.
- `+` Normal straight VMF gate writer now consumes measured trigger extents and lane-positioned arrival landmarks; existing car/glass barricades translate to measured lane centres. Legacy geometry is preserved and normal-wide emission remains guarded until runtime integration.
- `+` Current experimental client-local additive CSM accepted with default-off Options enable and Low1/15Hz, Medium2/30Hz, High3/rendered-frame tiers; baked/shared lighting unchanged.
- `+` User accepted the live motorway gate and alignment checks; transition availability follows world-data exits rather than gate-geometry validation.
- `+` Two corrected on-ramp comparison BSPs staged in content and engine maps with hashes matching their isolated builds.
- `+` User set the revised order: Cell Health Manager next, followed by full-map navmeshes and screenshots.
- `+` Preview cell materials and browser thumbnails now match all336 active runtime map names; 336 stale -edge2 material images were removed.
- `+` Read-only preview Cell Health Manager developer grid checks navmesh files and current-map captured photos without changing artifacts.
- `-` Reconciled milestone reporting: accepted motorway fixture review is preserved; historical join limits are not new asset-authoring requirements, and compile completion is not normal-generator or live-travel acceptance.
- `?` Safe-zone detail Phase M rejected after review; claim/reservation/emission integration removed. Authored assets and existing den entrances preserved; larger ordinary authored tiles are the replacement direction.
- `?` Phase E end-to-end output verification, authored origins and ring/travel integration remain unfinished; no new ordinary rectangular building asset is installed. Remaining CSM work is deferred outside Alpha 3.2 completion gates.
- `?` Weighted nested projectors are not proven seamless cascades; the user accepts the current CSM checks for now, while multiplayer isolation and matched foreground performance remain unverified and deferred.
- `?` Alpha 3.1.5 Phase D generated-output acceptance and Phase I integration move to the final shared output and closure phases J/K, without implying completion.
- `?` The retained preview compile completed336/338 with two motorway-crossroads failures; minimal brush repair is approved and attempted but uncompiled. That plan still lacks normal measured assembly integration and cannot be staged as a completed widened world.
- `?` The two-cell runtime map-name overlay, refreshed cell materials/thumbnails and Cell Health Manager UI have not been live-loaded or visually reviewed; the current world revision hashes remain until the final all-map output batch.
- `?` Cubemap completion remains unverified because BSP-packaged VTFs may be compiler defaults; the Cell Health Manager counts cubemaps as incomplete until reliable evidence exists.
- `?` The full corrected plan still includes additional recipe-name differences that are not activated. Do not expand them while generator work is paused.
- `?` User reports current CSM checks work and accepts them for now; no new performance, lifecycle or multiplayer evidence was collected.
- `?` The all-map navmesh/screenshot batch is deferred until Cell Health Manager completion; production rebuild and Workshop publication remain separately gated.

### 3.1.5 - Expanded City Edges and Launcher Presentation

**Status: in development | Date: 2026-10-06**

Phases A/B/C/E/F/G/H accepted. Remaining Phase D output acceptance and Phase I integration were carried to final Alpha 3.2 phases J/K on 2026-10-13; milestone closure is not accepted.

Development notes:
- `+` Gated deterministic outer-edge generation, tagged pools, coast omissions and shared core/traversal/visual bounds.
- `+` Isolated layout metadata, revision-distinct maps and core-only spawn eligibility for enlarged cells.
- `+` Corrected incompatible new-edge trees/signs without moving or replacing authored models.
- `+` Land/coast Hammer and isolated in-game geometry reviewed and accepted; launcher and survivor state restoration verified.
- `+` Phase A accepted; integrated gameplay limits carried into later phases.
- `+` Shared 5760 skyline pitch and versioned plan/coast compatibility; original beach and 2240 omitted-side attachment retained.
- `+` Corrected Storm Drain/west-ocean omission: existing border tiles retained, only western outer scenery omitted; skyline shoreline meets the old border without an intended gap.
- `+` Up to six stable cosmetic fires and smoke plumes on current-cell outer-edge building rooftops; existing fire toggle and distant effects retained.
- `+` Isolated skyline, snow, tower, recursive-cache, mesh-seam and packaging checks pass without replacing installed assets.
- `+` Phase B accepted on accumulated expanded-preview review, including corrected west coast, bridge continuation and current-cell edge fires.
- `+` Phase C accepted: expanded gates, deck-correct arrivals and road arrows passed accumulated static, compiled-map and live travel review.
- `+` Static depth-tested exit arrows follow road and bridge decks; motorway exits have paired carriageway arrows instead of a median arrow.
- `+` Live exit-arrow overlays in the HUD minimap and satellite/Level view retain carriageway placement and current route colours without baking arrows into captures.
- `+` Existing illustrated Satellite artwork is now Atlas; old Atlas presentation retired from the selector, with saved selections migrated.
- `+` Captured-world Satellite mode supports revision-gated complete imagery and saved clear/atmospheric variants; incomplete captures are not presented as a complete map.
- `+` Added 24 CS 1.6 firearms to the weapon loot pool using ZombieSim ammo, item scaling, holstering and effects; existing weapons retained.
- `+` Completed the 24-firearm CSS arsenal, including dual Berettas; added HL2 .357, SMG, pulse rifle, shotgun and projectile crossbow with inventory ammunition.
- `+` CS 1.6 variants now gain 25% damage, 20% range/capacity and 15% faster firing/reloads, multiplying existing random/mastercraft attributes.
- `+` Added imported hammer, machete, spanner and Lewis weapons; equipping the radiation suit uses HEV Gordon and hands without altering saved survivor appearance.
- `+` Options Third Party Licenses opens a scrollable collection of shipped original notices and clearly labelled creator-permission records.
- `+` Slower walk/sprint pacing with unchanged stamina capacity, drain, recovery and exhaustion rules.
- `+` Searchable props and fallen bodies use half activation and deterministic 320-unit 3D spacing; runtime drops are unchanged.
- `+` Rebuilt-map loot revisions atomically back up and reset only the affected profile/logical cell once.
- `+` Phase E accepted after automated persistence/rollback checks and corrected live city-cell search review.
- `+` Phase F read-only survivor cards show saved full-body appearance, clothing, location and active-weapon visuals through a bounded retrying client queue.
- `+` Phase F accepted after automated isolation/resource checks and direct review of Jim's saved full-body card, clothing and active weapon.
- `+` Phase G prototype uses reviewed public-domain Natural Earth art with generated night-light, cloud, distress and rim layers on bounded static meshes.
- `+` Selected survivor presentation can show one revision-matched saved-cell skyline model with an explicit marker and label.
- `+` Phase G accepted after the cache-corrected Earth and selected-cell city views passed foreground smoothness and presentation review.
- `+` Phase H Home now exposes exactly Play, Tools, Settings and Exit; Play opens survivor selection without deploying.
- `+` Home and Play now use interruptible atmospheric handoffs: a marked city location grows into a smooth descent before the daylight destination appears behind a full-cover veil.
- `+` The Play destination seats its bounded neighbouring-cell skyline cluster into enlarged rolling textured terrain, roads and a boundary-hiding ridge, with authored building materials and controlled daylight.
- `+` The authored preview launcher now places Earth and city presentation in its real scale-16 3D-skybox pass instead of an enclosed starfield room.
- `+` Home now uses the supplied transparent Z-Nation logo at its native aspect with bounded breathing and grunge framing.
- `+` Human review approved the marked descent, enlarged grounded daylight diorama and multi-weapon survivor boxes.
- `+` Home-only Earth controls add bounded drag rotation, wheel zoom and Reset View without changing the survivor's saved location.
- `+` City launcher Tools retains profile-safe Item Atlas, Content Status and Sky Browser actions while visibly disabling preview-only Map Atlas and Wardrobe.
- `+` Phase H accepted after human launcher presentation/control/lifecycle review and focused actual-client checks.
- `?` Phase 0 accepted: authored edge inventory, verified restoration copies and focused launcher baseline; remaining baseline limits carried forward.
- `?` Uncaptured individual visual cases and matched performance remain validation limits, not pending Phase B gates; expanded preview is temporarily staged with restoration backups.
- `?` Current-cell full-footprint projection is accepted; remaining Phase D world artwork/wireframe/Satellite output review is carried to final Alpha 3.2 phases J/K.
- `?` Options scroll height includes both footer buttons and bottom padding so Third Party Licenses remains fully reachable in the launcher.
- `?` Consolidated approved archive imports and hash-owned packaging into import_assets.py and imported_assets.json; original CS 1.6 and machete credits retained.
- `?` Distinct occupied-slot, legacy-state and saved-den card comparisons were unavailable and remain explicit validation limits.
- `?` Phase G began with one distressed Earth and selected-cell city prototype after its exact asset source was approved.
- `?` Destructive launcher confirmations, live city Settings, resolution-change review and matched foreground performance remain explicit Phase H limits.
- `?` Planned border-aware generated map previews remain acceptance-deferred for the later bundled output pass.
- `?` Production rebuilds and Workshop publication remain separately gated.
- `?` Alpha 3.2 generator-first work precedes the carried Alpha 3.1.5 closure; CSM projector/replacement-lighting feasibility gates are retained.
- `-` Fixed expanded black floor/sky enclosure beyond the west-ocean border; physical shell now follows the original 2240 shoreline attachment.
- `-` Motorway arrivals now trace a clear carriageway behind the arrows instead of using a median-centred landmark inside the concrete reservation.
- `-` Music duration is optional; City E now uses its full decoded replacement track instead of rejecting the stale 184.2-second duration.
- `-` Made all CS 1.6 variants loot-only at one-hundredth of their normal counterpart's weight; removed their quartermaster stock while retaining original offers.
- `-` Corrected generated bridge-deck gate height together with barricades and arrival landmarks; isolated structural checks pass, not yet staged.
- `-` New loot generations place one or two fallen bodies while unexpired legacy generations retain their saved body layout.
- `-` Fixed fingerprinted cold-start loot initialization so rebuilt-map safety cannot suppress every searchable spot.
- `-` Fixed wide-card camera framing that cropped survivor heads and added icon-model fallback for weapons without an explicit world model.
- `-` Character creation now rejects unknown profession input instead of authorizing it through the stored-data Civilian fallback.
- `-` Fixed the selected-cell launcher preview reparsing full world and skyline data every frame; profile and survivor-revision caches remove the severe live stall.
- `-` Ordinary launcher space hides only the 3D-skybox water and uses the approved night cube; sky inspection retains its separate water, selected sky and fog.
- `-` Survivor selection now uses three compact slot tabs and one ruled dossier with a bordered backgrounded portrait, face-safe framing and an icon-backed box for every equipped weapon; the posed weapon and duplicate strip are removed.
- `-` Cancelling Create at its first editable step now returns to the survivor grid; page changes release Earth input immediately.
- `-` Failed content checks and request timeouts now preserve the page that initiated them instead of unexpectedly returning Home.

### 3.1.0 - Skyline, Coastline, Clothing and Skies

**Status: development complete | Date: 2026-10-06**

Development accepted: city skyline and world edges, artist workflows for signs and clothing, and optional client sky palettes. Workshop publication remains deferred.

Development notes:
- `+` Skyscrapers integrated into city density with a centre-weighted skyline (Phases A-B, accepted).
- `+` Artist-friendly sign and billboard workflow (Phase E, accepted).
- `+` Wardrobe clothing catalogue: hundreds of fabrics, chest/back/thigh/cuff prints, shared blood overlays and independent outfits per citizen zombie (Phase F, accepted).
- `+` Integrated preview review and Workshop packaging foundations (Phase G, accepted).
- `+` Preview launcher Tools tab: Item Atlas, Map Atlas, Wardrobe, Sky browser and Content Status.
- `+` Clothing item icons show a fabric swatch with shirt/pants and pattern badges.
- `+` Sleeve-hem clothing prints and artist control over repeating patterns.
- `+` Both-arms and both-legs cuff prints; sleeve flames now climb up the arm.
- `+` Changelog viewer from Options, in the launcher and in game.
- `+` Optional sky palettes: sky browser, automatic and custom palettes, aerial sky preview and grouped Options (Phase H, accepted).
- `+` Authored launcher sky tours with smooth bird-like flight, context haze, preview music and an ending blackout.
- `?` Redesigned shoreline with waves and distinct cardinal world edges (Phases C-D, accepted).
- `?` Workshop publication remains deferred; development acceptance is not a public release.
- `-` Tropospheric night 1 removed from selection and packaging; saved choices and affected automatic profiles use night 2.

### 3.0 - City Presentation, Survival and Economy

**Status: released | Date: 2026-10-04**

Develops the city-world presentation and the survival, interaction and economy loops.

Development notes:
- `+` Player item protection and clearer interaction outcomes.
- `+` NPC interaction and service navigation in dens.
- `+` Economy and trading with an editor preview.
- `+` Radiation, damage and target feedback; radiation-responsive zombies and gore.
- `+` Environment and safe-zone music, movement and combat balance.
- `?` 3D skybox prototype, city generation, tile and foliage improvements.

### 2.9.2 - Client Performance and Quality Presets

**Status: released | Date: 2026-10-02**

Reduced client frame cost of weather and atmosphere systems and added Low/Medium/High quality presets.

Development notes:
- `+` Configurable quality presets for weaker or stronger hardware.
- `+` Hook profiler baselines for matched performance comparisons.
- `?` Cheaper snow cover, compass and atmosphere hooks with less per-frame Lua allocation.

### 2.9.1 - Build Pipeline and Test Organisation

**Status: released | Date: 2026-10-02**

Faster, better-reported world builds.

Development notes:
- `+` Bounded multi-process map compiling.
- `+` Fast preview and final compiler presets.
- `+` Step-by-step world generation logging.
- `?` Portal budgets raised to 750 clusters / 1,350 portals.
- `?` Lua test suites moved to gamemode/tests/.

### 2.9 - Gameplay, HUD, Transitions and Atmosphere

**Status: released | Date: 2026-10-02**

Reworked den camera and gates, HUD, weapon presentation, weather and gore.

Development notes:
- `+` New HUD with ammo display and slot-key badges.
- `+` Muzzle flashes, tracers, casings and recoil.
- `+` Weather, puddles, snow cover, fog, film grain and cinematic cell transitions.
- `+` Runtime foliage and debris, dismemberment and gore, entity loot targeting.
- `+` World map render modes and level view.
- `?` First-person den camera, reworked entrances and tunnel exits.

### 2.8.6 - Landmark Safe Zones and The Storm Drain

**Status: released | Date: 2026-10-01**

Safe zones per landmark rather than per environment, with placed 3x3 entrances.

Development notes:
- `+` Landmark-specific safe-zone configuration with cell_safezone as the default den.
- `+` Safe-zone entrance tiles placed beside roads by the planner.
- `?` The Evac Zone renamed to The Storm Drain at 0,0.
- `?` Preview world regenerated and staged.

### 2.8.5 - Launcher and Character Menu

**Status: released | Date: 2026-10-01**

A launcher room with a menu, rotating globe and full character creation.

Development notes:
- `+` Main menu with rotating globe, options, credits and exit to Garry's Mod.
- `+` Three character slots with load and edit screens.
- `+` Character creation: appearance, player model, profession and starting attributes.

### 2.8 - Weapons, Ammo, Food, Crafting and Trading

**Status: released | Date: 2026-09-27**

Counter-Strike: Source weapons, ammunition and the first den economy.

Development notes:
- `+` CSS weapon catalogue with realistic rarity and attributes.
- `+` Inventory-backed ammunition types and firing modes.
- `+` Scavenged resources and a tiered food system.
- `+` Validated recipes and atomic den crafting.
- `+` Professions with daily den deliveries, implants, mastercrafting and offline trading.
- `+` Mounted asset catalogue and semantic world loot.

### 2.7 - Items, Loot, Enemies and Bosses

**Status: released | Date: 2026-09-26**

Data-driven items, loot rolls, enemies and bosses.

Development notes:
- `+` Static data registries for items, loot, enemies and bosses.
- `+` Persistent item instances with scaled attributes.
- `+` Loot composition and world loot spots with cell refresh.
- `+` Inventory and loot interface, boss lifecycle and world markers.

### 2.6 - World Generation Fixes

**Status: released | Date: 2026-09-26**

Corrected tile orientation and the rules of procedural world generation.

Development notes:
- `?` Fixed tile road-connection direction markers and building rotation toward roads.
- `?` World generation rules and multi-tile template fixtures.

### 2.5 - Item and Loot Prototypes

**Status: released | Date: 2026-09-22**

Design groundwork for the 2.7 item system.

Development notes:
- `+` Pseudo-prototypes for the new item, loot and spawn systems.
- `+` Completed prototype document with code examples.
- `?` Assorted fixes and tweaks.

Historical record reconstructed from available project history.

### 2.0 - Zombie Walker Simulator

**Status: released | Date: 2026-09-11**

The independent C++ walker population simulator.

Development notes:
- `+` Finished the portable C++ zombie walker simulator.
- `+` New city tiles.
- `-` Broken tile thumbnails removed.
- `-` Compiled city maps no longer tracked in the repository.

Historical record reconstructed from available project history.

### 1.4 - Scoreboard and Persistence

**Status: released | Date: 2026-09-08**

Development notes:
- `+` New scoreboard.
- `?` SQL persistence fixes.
- `?` Preview world updated.

Historical record reconstructed from available project history.

### 1.3 - Release City and World Map

**Status: released | Date: 2026-09-07**

Development notes:
- `+` First rendered release city.
- `+` In-game world map.
- `+` Variable tile sizes.
- `?` Improved carpark engine and city layout.

Historical record reconstructed from available project history.

### 1.2 - Safe Zones and Atmosphere

**Status: released | Date: 2026-09-06**

Development notes:
- `+` Safe zones.
- `+` Atmosphere profile system.
- `+` Desert test profile and new FGD.
- `?` General fixes.

Historical record reconstructed from available project history.

### 1.1 - City Generator

**Status: released | Date: 2026-09-05**

Development notes:
- `+` Procedural city generator.
- `+` Generator settings and expanded documentation.

Historical record reconstructed from available project history.

### 1.0 - Foundations

**Status: released | Date: 2026-09-05**

The first commit of the gamemode.

Development notes:
- `+` Initial gamemode.
- `+` Third-person camera.
- `+` Attribute system.
- `+` First HUD elements.

Historical record reconstructed from available project history.

## Historical marker key

- `+` ? added
- `-` ? removed
- `?` ? changed, fixed or in progress
