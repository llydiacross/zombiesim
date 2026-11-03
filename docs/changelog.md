# Developer Changelog

Internal engineering history for ZombieSim. The player-facing changelog is maintained in [changelog.json](../content/data_static/changelog.json).

## 2026-11-02 - Alpha 3.5 planning

- Made Alpha 3.5 the active tracker for the user's city-generation goals and
  unfinished Alpha 3.3/3.4 work. Archived both prior trackers without declaring
  them released or fully accepted; existing deferrals and output approvals
  remain in force. No generation, compilation, staging or live testing ran.

## 2026-10-28 - Prefab editor live continuation

- The user confirmed the editor workspace, prop placement and gizmo interaction. A visible valid-ID save failure exposed unsynchronized text-entry values; the editor now updates metadata while typing and synchronizes visible fields before save. Focused fixtures pass, and the user confirmed save/reopen with a one-prop prefab.
- Added a larger paged, searchable model-thumbnail browser and a ground compass. The user confirmed both work in game and accepts the browser for now, with a separate UI-refinement phase deferred. The player returned to the launcher after the save check and persisted city/preview data matched the baseline; the editor was then reopened for this review.
- The user requested selectable 3D reference tiles and bright/dark editor lighting, with fog controls. A read-only inventory found 227 authored tile VMFs outside the development zoo. The user approved one straight-road model: its isolated compile and 13 structural checks pass, and 18 temporary content/game files were hash-staged with a reversible ledger. Focused fixtures pass; the user confirmed the road's appearance/alignment, fog, simulated dark grade and removing the reference in game. The extractor omits underside faces and is not a general tile converter; broad generation remains gated.
- The user requested a separate A3 editor-UI phase organized around clear workflow areas, beginning with a top-left Prefab button opening its side panel. The current model browser remains functionally accepted; the road selector's discoverability and broader visual simplification belong in that later phase.
- The user saved and reopened a two-prop `test123` prefab, then returned to the preview launcher; stored city/preview persistence again matched the baseline. They requested double-click mode cycling and selected uniform scaling first. Source now supports bounded 0.1-10 uniform scale and preserves older unscaled documents; focused fixtures, 16 export assertions and GLua syntax 295/0 pass. Live scale review and gameplay collision remain open.
- After the first live scale review, the user confirmed mode cycling but reported that only the bounding box changed size and the handles lacked visual mode cues. The preview now uses a client render-scale matrix with scaled bounds and distinct move arrows, rotation rings and scale squares. Focused fixtures pass; the actual visual fix still needs a fresh-load review. Stored survivor data remained unchanged after returning to the launcher.
- The user confirmed the prop now visibly scales and its saved size restores, but reported awkward rotation. Ring dragging now follows the cursor's intersection with the selected rotation plane, with signed angular movement and wraparound; pitch/roll rings follow prop orientation. Focused gizmo/client fixtures and GLua syntax pass. Fresh in-game rotation review remains pending.
- The user revised ring selection after the initial double-click lock: one click highlights a ring, a held left-button drag anywhere in the viewport rotates it, and a click elsewhere without dragging deselects it. Releasing a drag retains the selection; right-click during a drag cancels that drag. Client fixtures pass 24/24, atmosphere fixtures 18/18 and GLua syntax 295/0. Following a same-map reload, the user confirmed the interaction, crossings, snapping, camera orbit and prop mode cycling work. On return to the preview launcher, the session marker was absent and the stored city/preview persistence hash matched the baseline.
- The user also requested middle-click rotation reset. Source resets only the clicked prop's local orientation, preserving position and scale; focused fixtures cover ordinary, empty-space and active-drag cases. The user confirmed the reset works in the live review.
- Added the initial shared prefab explorer in source, accessible from launcher Tools and the editor. It supports search/exact-tag filtering, assembled interactive 3D previews, and confirmed rename/delete with stable IDs. Server requests validate preview-admin/editor access and protect the document currently open in the editor. The user confirmed launcher preview, search, orbit/zoom and close behavior, and identified the missing launcher **Open in Editor** action. After the action was added, the user confirmed it loads the selected prefab, that the editor explorer opens, and that rename/delete/filtering work with a disposable prefab. Offline explorer6/6, editor24/24, session10/10, packaging68/68 and GLua297/0 pass. After return to the launcher, the editor marker was absent and stored city/preview persistence matched the baseline.
- The user requested substantially closer editor zoom and possible additional camera controls. Recorded for the separate A3 UI phase; behavior still needs agreement and no camera changes were made in this slice.
- Added an in-memory storage round-trip case using GMod's actual JSON serializer for three-decimal local transforms, scale and four cardinal yaw values. Fresh live `zn_test_prefabs` passes 15/15. World-anchor rotations, spawned overlaps and scaled gameplay collision remain later integration checks.
- The user accepted the A1 editor/explorer authoring slice with those integration limits, and approved continuing to A2. A3's closer zoom and possible camera controls remain deferred.
- A2 decisions: runtime uses explicitly exported addon prefabs; multiple anchor tags all must match; guaranteed prefab loot bypasses the activation roll and spacing. A source-only exported catalog and deterministic selector pass two offline fixtures and GLua299/0, but are not wired into world spawning. No maps or prefab exports were generated.
- The user chose per-prop stationary/movable behavior, with moved props resetting to their authored placement on each cell load. The editor setting, document/storage contract and export validator preserve that choice, with legacy and new props defaulting to stationary. Focused editor25/25, storage7/7, contract6/6, export23 and GLua299/0 pass; a fresh launcher start passed live prefab contracts17/17. The user confirmed per-prop setting and save/reopen with a disposable prefab; after return, the editor marker was absent and stored survivor data matched the baseline. World physics remain unimplemented.

## 2026-10-29 - Prefab spawn primitive

- Added validated unscaled native prop creation, anchor-local transform composition, per-prop motion flags, anchor-owned cleanup and rollback of partial failures. Non-unit scale is explicitly blocked pending collision verification.
- Offline spawn fixtures pass 2/2 and GLua syntax 302/0. A fresh preview-launcher engine fixture passes 1/1 across four cardinal anchor rotations and both motion flags. This is creation/flag evidence, not sustained motion, collision or visual acceptance.
- Normal map spawning and the Hammer entity remain unwired. Their integration requires custom-point instance-transform handling and an approved bounded compiled fixture; no world outputs or authored templates changed.
- Subsequently, the user approved narrow anchor integration and one isolated compile. The Hammer entity, FGD, instance transform emitter and server runtime owner are now wired; direct anchors coexist with transformed tile anchors. Runtime-owner6/6, spawn2/2, packaging68/68 and GLua306/0 pass. The corrected one-map fixture passes VBSP/VVIS/VRAD, 4 clusters/4 portals and 27 compiled-entity checks. Staging, live map-anchor review, scaled collision and prefab loot/gate integration remain pending.
- A bounded engine probe now checks stationary/movable oil-drum server collision on all axes at scales 0.1, 0.5, 1, 2 and 10 against an unscaled control; `zn_test_prefab_spawn` passes 2/2. It does not prove client/gameplay collision, so scaled spawning remains blocked.
- Fixed early survivor-spawn ordering: loot waits for deferred prefab initialization, and still starts after a reported prefab failure. Offline runner12/12, runtime owner7/7 and GLua306/0 pass; fresh launcher loot19/19 and spawn2/2 pass. Actual city-cell ordering remains unverified.
- With explicit approval, staged only the isolated anchor BSP and one temporary exported prefab using a hash-verified ledger. The owner-only session loaded no survivor; five compiled anchors selected the fixture and spawned ten unscaled props under synthetic cell0. The user confirmed placement/rotation and stationary/movable collision. After return, the editor marker was absent, stored city/preview persistence matched the baseline, and all ledger-owned temporary files were removed. Normal city-cell eligibility, loot and scaled collision are still unverified.
- Implemented per-prop Off/Normal/Guaranteed loot authoring, validated loot-group overrides and optional Normal activation chance, stable prop IDs and profile/cell-scoped spot keys. Guaranteed spots bypass the roll and spacing and merge atomically without resetting searched state. Fresh live prefab19/19, loot23/23 and isolated spawn3/3 pass; offline editor26/26, session12/12, spawn3/3, owner8/8, export28 and GLua308/0 pass. An initial selection-loop failure and later nested-include timeout were fixed and retested. The user confirmed the editor settings and save/reopen with a disposable prefab; after return the editor marker was absent and stored survivor data matched the baseline. City-cell loot review remains pending.
- The user requested a discoverable list of available loot groups instead of requiring a typed ID. Recorded for deferred A3 editor-UI work, with server-side validation and the model-default option retained.
- Fixed a tightly coupled existing loot-claim failure: persisted spot consumption and inventory grant now share one transaction, so spot-write failure, inventory-write failure, stale offers or profile mismatch cannot duplicate rewards. Decline/encoding/missing-row failures surface explicitly; temporary runtime drops retain their separate path. Fresh live loot30/30, inventory51/51 and isolated prefab spawn3/3 pass; actual deployed city-cell review remains pending.
- Scaled oil-drum fixture traces exposed a client/server collision mismatch. The nonzero scale-transition experiment made server collision wrong too and was reverted. Explicit client activation, then a fixture-only automatic network sync, brought client/server traces within 0.002 units on a fresh fixture load; the user confirmed walking and pushing. Baseline/marker and hash-ledger cleanup passed. This single-client fixture does not establish PVS leave/re-entry, other models, multiplayer or deployed gameplay; normal-world scaling stays blocked.
- The user chose temporary mounted-prop roadblock/gate examples and a separate isolated review, with existing gate cars unchanged. A source-only north–south-road fixture and distinct tag selection now pass 9/9 and 3/3 respectively; transition server12/12/client11/11 and GLua313/0 pass. It contains no trigger and has not been compiled or staged.
- Prepared a guarded city-context prefab loot probe using a transient prop, unique throwaway loot profile and automatic decline, with no intended player movement, cheat changes or inventory grant. Offline safety2/2 and GLua315/0 pass; the launcher correctly rejects the non-deployed context. The user chose to deploy their existing preview survivor; the actual city probe remains pending.
- The user deployed their existing preview survivor in logical cell14,0. Read-only status verified the map and active loot cell302; the real-city probe passed1/1 for candidate selection, targeting, search, decline and throwaway-profile reload. Position and inventory were unchanged during the probe, the active loot owner was restored and the marker absent. After user-approved return, the saved cell and stored city/preview persistence matched the baseline. The test used a synthetic anchor and did not verify an accepted reward, multiplayer or scaled collision. Final cleanup verification was strengthened afterward and is offline-tested only.
- The user approved one isolated set-piece compile. VBSP/VVIS/VRAD pass, within budget at 4 clusters/4 portals; 15 source/BSP assertions verify the two references and anchors and no trigger. The known sky texture warning remains. Reversible set-piece staging passes 11 fixtures; no set-piece map or prefab has been staged.
- The user then approved temporary staging and confirmed both road references and placeholder arrangements looked correct in the isolated room. Two compiled anchors selected the intended test prefabs and spawned five props with no survivor loaded. After return, the editor marker was absent, stored city/preview persistence matched the baseline, and the hash-verified temporary files were removed. The scene had no travel trigger and is not final gate artwork or gate-travel acceptance.

## 2026-10-28 - Credits follow-up planned

- Added the supplied credits song and four dancer heads tracking the current credits camera to Alpha 3.3 Phase D. The existing credits presentation and engine music-volume control must remain intact; per-model ragdoll behavior and live appearance need verification.

## 2026-10-28 - Prefab readiness started

- The user authorized Alpha 3.3 implementation. Confirmed `gm_flatgrass` exists and traced launcher and survivor spawn ownership; a safe editor session cannot simply reuse ordinary non-launcher spawning.
- Confirmed the documented GMod DATA write and local-to-world transform APIs. The user chose preview-launcher admin access with no other connected humans, server DATA saves with explicit addon export, 3D mouse gizmos plus numeric controls, and a two-prop fixture. No editor code, map change or player-data change has occurred yet.

## 2026-10-28 - Prefab editor source prototype

- Added the initial isolated preview-launcher/flatgrass editor session, server-DATA prefab validation and storage, model browser, 3D gizmos/numeric controls, and explicit dry-run-first addon export. Exported definitions are included in the Workshop core inventory.
- Offline fixtures pass 21 cases; export passes 13 assertions, packaging 68 and GLua syntax 295/0. A preview admin was confirmed and the same launcher map reloaded with `-disableluarefresh`. The in-game prefab suite timed out without acknowledgement or a report while a separate slot probe succeeded; the current in-game error is needed before retry. No live editor, visual review, two-prop fixture or survivor restoration has yet been verified; map generation and city prefab spawning remain out of scope.
- The user supplied the resulting nil-factory error. The test registration now receives dependencies from the gamemode entry point rather than using nested relative includes; its offline registration fixture passes 11/11. After a fresh preview-launcher reload, `zn_test_prefabs` passes 11/11. The two approved fixture models resolve from the installed `hl2_misc_dir.vpk`; editor and survivor-restoration review remain open.
- The first live editor entry reached `gm_flatgrass` but the workspace trace stopped above its actual ground; the user also observed a danger-star HUD error. The trace now uses the map spawn elevation, the star vertices are initialized before their triangles, and gameplay HUD/crosshair are suppressed in the editor. Focused offline regressions and GLua syntax pass; the player returned to the preview launcher and stored city/preview data matches the pre-editor baseline. Reload and a fresh editor retest remain pending.

## 2026-10-28 - Calling-card pipeline planning

- Expanded Alpha 3.3 Phase D with an artist-source pipeline for standalone handcrafted PNGs and JSON-configured generated backgrounds/details, including repeating emblems, full-cover patterns, a runtime catalogue, safe staging and packaging checks.
- Kept prefab work first and left calling-card ownership, naming and other phase-specific decisions for their design gate. No pipeline, generated assets or staging was created.

## 2026-10-28 - Scoreboard default artwork

- Moved the existing scoreboard background and detail PNGs into their respective `backgrounds/default.png` and `details/default.png` paths and updated the client references. Their contents and dimensions are unchanged.
- The user confirmed additional calling-card variants have not yet been created. Calling-card ownership and UI remain future Alpha 3.3 work; the root `data_static` audit remains deferred.
- Validation: GLua syntax passes 281/0, and the isolated packaging suite passes 67 assertions, including both new paths. Garry's Mod was not running; visual verification remains open.

## 2026-10-28 - Alpha 3.3 planning

- Archived Alpha 3.2 without declaring release or full acceptance; retained its uncompleted output, maintenance and carried 3.1.5 closure work as deferred.
- Set Alpha 3.3 to planning: prefab editor first, zombie AI medium priority, fog least-priority presentation work, and world-generator rules last. Other ordering is proposed rather than user-approved.
- Preserved the author's Alpha 3.3 notes and added phased requirements, current owners, decision gates and validation. No implementation, generation, staging or live work was authorized or performed.
- Updated the in-development version/changelog metadata and corrected existing 3.2 and 2.6 highlight group ordering without changing their text.

## 2026-10-28 - Trusted motorway source cleanup

- Retired the mouth/connector survey, measured assembly-report workflow and complex inspection modes; normal planning, gate emission and runtime export use the matching approved trusted-plan records.
- Retained grid-aligned road placements, trusted leases and straight inspection. Made preview inputs explicit and corrected the retained full-plan regression to use the matching corrected plan.
- Focused source checks pass: contracts 132 assertions, retained grid/VMF and gate writer/export checks 1464, infill scope 6, and saved gate/entrance checks for all 96 motorway cells. PowerShell parsing passes 121 files; `git diff --check` passes.
- No world generation, compile, staging or live reload was performed. Compiled and live verification of the cleaned-up pipeline remain pending; previous motorway visual/travel acceptance is unchanged.

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
