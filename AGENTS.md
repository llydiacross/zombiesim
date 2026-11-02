# ZombieSim Agent Guide

ZombieSim is an installed Garry's Mod gamemode. It combines realm-specific Lua gameplay code with a PowerShell pipeline that generates and compiles reusable Source VMF recipe maps.

## Future-agent rule: keep the contract simple

- Start from the user's explicit behavior rule and the existing authoritative
  owner. For travel, `ZM_World` connectivity/accessibility decides whether a
  neighbor is reachable; a transition trigger supplies direction. Do not add
  geometry matching, face-ID checks, tolerances, or compatibility defaults as
  access vetoes when that rule already answers the question.
- Keep access decisions separate from presentation and arrival safety. Optional
  geometry probes may position arrows or select a safe arrival, but must not
  overrule an accessible world-data route.
- Preserve canonical placement rules. Ordinary roads stay on the 640-unit
  5x5 grid; motorway leases reserve/suppress grid slots rather than moving
  roads to match measured mouths. Do not request per-cell offsets or reopen
  user-approved motorway art.
- Prefer one reproduced failure and the smallest owner-level fix. Add only
  checks required by the contract; do not pursue mathematical perfection,
  duplicate state, or schema/fingerprint machinery without a demonstrated need.
  Treat diagnostics as diagnostics, not new requirements.
- In preview/dev data, do not hide stale or incomplete exports behind a
  backwards-compatibility default. Either produce the current source data or
  stop depending on that optional metadata.

## Active Task Tracker

**Tracker restructure (user, 2026-11-02):** the world viewer, new-tile
wiring and generation changes (formerly Alpha 3.4) now close Alpha 3.3 as
[Phase J](todo-alpha.3.3.md); the user approved the viewed world. Unfinished
Alpha 3.3 phases E (player structures and claims), F (asset staging/
refactors), H (world-generation output batch) and I (closure) moved to
[todo-alpha-3.4.md](todo-alpha-3.4.md), which continues 3.3 with the
structure system first. Settle Phase E's design gate with the user before
coding. Satellite, compiling, staging, navmesh and Cell Health still need
separate approval. Tile-wiring decisions are recorded in 3.3 Phase J. The
user's new `tile_ra_building_2aaa/3aaa` and `edges/tile_edge_ra_wall_4aaa`
are wired into the isolated `generated/preview_alpha34_v2` data.
Phase E decisions are recorded in the 3.4 tracker. Source now exports
per-cell `claimTiles` (`bin/claim_tiles.psm1`) and `ZM_World` exposes
`GetClaimTiles`/`IsClaimableTile`/`GetCoreTileAt`; installed runtime JSON
is unchanged until approved preview staging.
`gamemode/sv_claims.lua` (`ZM_ClaimService`) owns claims: one
`itemClaimToken` is consumed in the same inventory transaction as the claim
insert, lapsed (30-day) claims are replaceable and never revived, and visits
refresh active claims for the owner's account and friends. Offline claim
fixtures 8/8 and GLua 401/0 pass; native `zn_test_claims` is written but
not run live. Construction (source/offline only, not live-tested): the
Hammer's Reload toggles build mode (`sh_/sv_/cl_construction.lua`), and
`zn_construction_piece` blueprints (foundation/wall) are placed inside
accessible claim tiles, paid atomically on first E contribution and fade in
when complete. Construction fixtures 14/14, GLua 407/0. Pieces are not
persisted; see the 3.4 tracker's Phase E for decisions and live unknowns.
**Paused (user, 2026-11-02):** the agreed next step is staging the preview
runtime JSON with `claimTiles` (backup first), a reload with the new Lua and a
bounded live construction review. Wait for the user to resume.

**Hammer asset staging (user, 2026-11-02):** Hammer reads only engine
search paths (`garrysmod/`, `garrysmod/addons/*`), not this gamemode's
`content/`. `bin/stage_hammer_assets.ps1` copies content-owned models (with
MDL/VMT/VTF dependencies) referenced by `tiletemplates`/`celltemplates` into
`garrysmod/models`/`materials`, hash-verified with an ownership ledger at
`generated/hammer_assets/staging-ledger.json`; it refuses to overwrite
unowned differing files. `build_tile_detail_models.ps1` runs it at the end.

**Skyline ra_ towers and view distance, 2026-11-01:** the distant-tower
filter in `bin/skybox_models.psm1` now accepts `tile_skyscraper_ra_*`
(regression in `test_skybox_towers.ps1`); `skybox-towers-v3` invalidates old
tower stamps. `skybox3d.neighbourRadius` is 6 and `maxTowerModels` 256; the
Options slider reaches 6 rings while presets stay Low1/Medium2/High2. The
rebuilt preview skyline (11 tower parts, all 6 ra_ recipes) is staged with a
backup/ledger entry; the user confirmed ra_ silhouettes and the 3-6 ring
slider work with acceptable performance. City skyline is unchanged.
The illustrated ATLAS/WALKERS image `map_layers/satellite.png` is excluded by
`stage_world_map_materials.ps1`; after a world refresh, rebuild it with
`build_world_satellite_material.ps1` (matching settings/plan) and stage it.
The rebuilt Alpha 3.3 preview atlas is staged with a backup/ledger entry.
Captured SATELLITE (revision-gated) and WIREFRAME (navmesh-backed) remain
stale for this world; the user deferred the Cell Health navmesh/photo batch.

**Calling-card D2 decisions, 2026-10-30:** unlocks are shared by a Steam
account's survivors within each world profile; only the two defaults are free.
Background/detail unlocks are independent, selections are per survivor and
visible to others. Buy with survivor credits at den traders; availability and
prices are per design, with quest rewards separately configurable. No quest
integration or live/multiplayer acceptance is implied.

**D2 calling-card source and offline checks:** account/profile unlocks,
per-survivor selections, scoreboard selector and atomic den-trader purchases
are source-wired. The server-only reward API is not integrated with quests.
Seven cards are installed, including the two free defaults. Phase D offline fixtures41/41, artist
pipeline88/88, packaging73/73 and GLua390/0 pass, including the isolated
server-suite fixture, server/client wire correlation and the cached-factory
bootstrap regression. The native calling-card suite passes4/4 and static-data
fixtures22/22; after the approved staging reload, static validation loaded
seven cards with zero errors and the existing Capitalist warning. The client
state fixtures passed4/4, but all six client UI fixtures failed because their
deferred loader returned nil. Source now caches the initializer during client
bootstrap and restores its environment even if a fixture fails; offline state4/4
and UI6/6 pass. After a user-approved preview-launcher reload, fresh client
reports pass state4/4 and UI6/6. After the reload and tests, 21 table row sets
match the verified pre-reload backup; the two new calling-card tables were
absent from that backup and remain empty. Separate status confirms the preview
launcher with one human, no editor participant and no loaded survivor, and a
fresh client report confirms ready Home. The user deferred live artwork/survivor
review; ask before another reload or deployment. Real UI, purchases and
multiplayer remain unverified.

**Calling cards approved (user, 2026-11-01):** the user reports the calling
card system is perfect with no issues. The scoreboard bio pencil overlapped
the Mechanics skill cell; source now docks a 28px button on the Survivor Bio
header row (GLua392/0); after a reload the user confirmed its placement and
editor.
**Phase G fog prototype (2026-11-01):** layered fog style and
`gamemode/skybox/cl_haze.lua` skybox ground haze are described in the
tracker's Phase G section; atmosphere19/19 and GLua392/0 pass. After a
reload the user said the haze looks good; weather/radiation/Low/performance
remain unsampled. `zombiesim_fog_style legacy` restores the
original fog exactly.
The next layer, `gamemode/atmosphere/cl_world_haze.lua` (in-world edge
curtains and pooled ground mist, `zombiesim_world_haze`), was live-loaded;
the user asked for stronger edges/mist, eased changes and a post-nuclear
radiated look. That tuning (eased fog, radiated fog/sky colour, horizon glow,
fallout ash) was reloaded on `zz_preview_49d203952b23-v1`. The top-down fade
(`ZM_GetTopDownCameraWeight`; layered fog density and world-haze curtains/mist
only; legacy, ash and skybox unchanged) is live and user-approved, as is the
free/shoulder fog. The user then rejected the green as too hazy against the red
sky: radiated fog now matches the sky's burnt orange, is slightly less hazy,
and rising fire embers join the ash (atmosphere25/25, GLua393/0); reloaded
live and user-approved. A 10 s foreground operation sample was taken on
`zz_preview_a39fe92b1e79-v3`, cell (14,-1), radiation 0.667, High, clear
weather. Results:

- Overall: 38.8FPS average, Lua hooks 5.89ms per frame.
- World haze: 0.62ms per frame (draw plus think).
- Skybox draw: 3.07ms per frame, the largest owner.

This is not a matched comparison. The user approved the Low preset's
appearance. Under Low, world haze cost 0.31ms per frame and the skybox draw
1.97ms per frame, at 56.9FPS. The moving cloud deck (72 clusters, drifting
faster, billowing) is user-approved. Storm lightning
(`gamemode/skybox/cl_lightning.lua`: skybox bolt, sky/world flash, distance-
delayed thunder) is user-approved live, except that the reduced-flash option
was not checked. A future first-run photosensitivity prompt will disable
flashes; it is deferred. Rain at building edges and the `cl_skybox` split come
next. After that, the queued requests in the tracker's Phase B: player
walk/sprint 15% slower with sprint lasting twice as long, walkers 25%
slower, and a walker on-screen capacity study. Ask before `changelevel`.
The user reported a flickering, striped z-fight at their cell's haze wall.
Edge curtains now zigzag in slanted pleats so none can be coplanar with a
wall face (atmosphere25/25, GLua394/0). The user confirmed this solved the
issue; the coplanar cause was not isolated. Billboard z-fighting is
noted in the tracker for later investigation.
The user-selected rain rework is source-wired in `atmosphere/cl_weather.lua`
and recorded in the tracker: sky-only spawning that keeps falling outside
while sheltered, a softer sheltered sound, a far forward band and bounded
roof-edge runoff. Atmosphere27/27 and GLua394/0 pass. A live fix makes
traces that hit nothing count as open sky. The user approved it live (open,
sheltered, drips, sound, performance fine), and the weather schedule was
resumed afterwards.
`cl_skybox.lua` is now a core plus section modules under `gamemode/skybox/`
(coast, edge terrain, clouds, activity, diagnostics, haze, lightning). A
load-time surface comparison matched, the edge report passed with 0 failures
and the user confirmed it looks unchanged. Put new skybox behavior in its
owning module.

**Noted for later (user, 2026-11-01):** the epicenter uses the settlement
cell. The user suspects this blocks the radiated border/edge pieces, so it
looks residential instead of destroyed. Verified cause: the 21 blast-core
cells resolve to profile `destroyed`, which had no border or outer-edge pool.
Settings now reuse the radioactive pools. Radioactive cells now prefer
`_ra_` buildings that fit the density tier, with industrial as fallback
(only `building_ra_1a` exists; the user will author aa/aaa). The approved
regeneration, which affects roughly all radioactive recipes, waits for the
Cell Health batch.
The ordinary-road/on-ramp dogleg regression is fixed in
`bin/motorway_grid_placements.psm1`: trusted `ordinaryRoadApproaches` are
restored (cells (13,18) S and (6,23) E, the latter extended by one native
straight). A baseline plan proves no other cell changed; the grid test
passes 1515. Both maps join that regeneration, uncompiled and unreviewed.
**Plan change (user, 2026-11-01):** the Cell Health batch was cancelled at
the user's request (1048/1142, verified restored to the Doctor at (3,-2)).
Next comes the world visualization tool, then the
generation changes now in Alpha 3.3 Phase J (commercial spread, fewer
parks/more leisure, police and fire in every district). The regeneration
above folds into that work and is reviewed in the viewer before compiling.
Source-only so far: `landmarks.commonWeights` (Park0.35) makes parks rarer
(seed-1337 Park37->22, Leisure27->42; equal weights byte-identical), and the
cell-map renderer now draws every ordinary `roads/*` piece as road and never
anchors landmark markers on them (`test_cell_map_artwork.ps1`). Nothing was
regenerated; preview cell materials/Satellite need an approved rebuild.

**D3 credits source, 2026-10-31:** the user confirmed the supplied
`content/sounds/music/credits.mp3` is cleared for inclusion and redistribution;
this is not independently verified licence evidence. Credits music now uses
the launcher audio owner, pauses/resumes the menu track, honors the music
toggle and `snd_musicvolume`, and stops on close or shutdown. Workshop
packaging owns the canonical `sound/music/credits.mp3` path. Offline
audio lifecycle11/11, read-only dancer-probe6/6, isolated packaging74/74
and GLua391/0 pass. After an approved preview-launcher reload, a fresh client
report confirms the probe is loaded and correctly reports inactive credits;
the launcher remains at Home with one human and no loaded survivor.
The preview-admin-only status command records the current credits camera,
music channel and four named ragdolls' head/eye matrices without changing
physics or poses. The user opened Credits and confirmed the song is audible;
the later client snapshot found credits inactive and did not capture dancers.
The user deferred a further dancer snapshot; do not retry it without agreement.
An active snapshot is still required before choosing head-tracking axes.
Do not claim that any head tracks or that D3 is accepted.

**Launcher Play fade, 2026-11-01:** the city diorama is gone. Play/Back fade
through black (0.22/0.1/0.4 s, `DrawOverlay`) to the authored `deploy_camera`
or the Earth. Page content and the day/night sky swap only at full black, and
panels reveal afterwards. Both launcher BSPs are restaged; the client suite
passes 24/24 and the user approved the preview transition. The city launcher
has not been reviewed live, and `buildcubemaps` remains a manual user step.

The user supplied `patterns/dirty_paper.png`, `symbols/creeper.png` and
`symbols/weed.png` for calling-card generation. The paper is byte-identical
to the existing default background; the symbols have transparency. The user
confirmed all three are cleared for use and distribution, including the
creeper; this is user confirmation, not independently verified licensing.
They chose a small preview with separate backgrounds and details. Three paper
colour variants and two tiled symbol details are generated under
`generated/callingcards_preview/build-a4288f7edf9a4f05b395c31dab649bd8`.
The user chose 5 credits per design at den traders, future quest rewards and
no player resale; unlocks are not backpack items. Its artwork is byte-identical
to the reviewed earlier preview; 750x125 dimensions, detail transparency and
unclipped sides passed there. The user approved the approximate six-combination
sheet for an initial in-game review, not final appearance. Isolated SQLite
exercised all five exact catalogue entries as purchases and rewards and rejected
resale; the expanded-catalogue fixture also passes14/14. The user approved
staging these exact five PNGs and the shared catalogue; all seven installed
materials and catalogue hashes were verified. The detail-default digest was
updated to match its current image, without modifying either default image.
The user deferred survivor review; do not deploy, purchase or select cards
without separate approval. No quests are wired.

The user reports an aesthetic redesign of the 1x1 roads and says a full
world recompile is required. Preserve the edited/new road VMF/VMX sources.
Existing BSPs do not yet include the redesign; inventory dependencies and
profiles in Phase H and obtain separate approval before the full compile,
matching output/staging or production changes.
**World-source requests, 2026-10-31:** user edited both launcher VMFs, many
roads (prefab anchors/visuals) and building tiles. Road connections gain
`parking` and `dual_driveway`, apply to the adjacent ordinary road (1x1 too);
per road: two driveways -> dual, driveway > parking > bus. New
`edges/tile_edge_ocean_*` pieces fill ocean-adjacent outer slots on every
west-ocean cell, with shell/shoreline moved out for a seamless
`blendrocksand004a` join. D3 dancer heads deferred. Recompile still gated.
Source status: connections wired (fixtures107/107); no authored parking
markers exist yet. Ocean pieces1a-9a are one pool, sea on canonical +Y,
yaw = land wall +180, NW/SW corners use W; bounds stay revision2 with coast
2880 = visual, all-side shell2880/2944, clip2240. Skybox beach now uses the
blend's `nature/sandfloor009a`; the rock embankment is skipped when coast
equals visual. Outer-edge units1186, skybox geometry11/11 offline and
GLua391/0 pass. Native world-bounds suite, compiled seam fixture, Hammer/
in-game seam review and full regeneration all remain unrun and need approval.
**Roads/empty cells, 2026-10-31:** `deadZones` retired; `road.antiGrid`
breaks long straight ordinary avenues (city9-16, preview5-8) into T-sections
or jogs, preserving origin reachability (`test_road_anti_grid.ps1`103 pass).
Roadless cells without safe zone/landmark become plan `emptyCells`: no
recipe/map/BSP, runtime `empty`, no exits, untravellable, drawn as one flat
terrain tile (`test_world_empty_cells.py`2/2). Isolated preview: 571 map
cells, 5 empty, 318 recipes vs installed336. Not regenerated or staged.

World-prefab placement is now source-wired: one explicitly enabled profile/
logical-cell/tile/XYZ-offset/rotation placement per document, independent of
tag selection. Saving remains server DATA; the existing explicit prefab
exporter preserves placement metadata, and core packaging includes exports.
No user prefab has been exported by this change. Disabled world prefabs stay
out of tag selection; re-export disables gameplay placement on the next cell
load. The editor adds suggested/custom tags and per-tab preview X/Y/Z offsets;
the explorer shows placement kind/location and tag suggestions. World rotation
is applied on cell load, not to the local editor preview.
Offline prefab35/35, export66, packaging70 and GLua376/0 pass. After a
verified empty-launcher reload, live prefab28/28 and native spawn7/7 pass,
including a runtime-created anchor's stable loot/light IDs. This is not
automatic deployed-cell, visual UI or multiplayer acceptance. Current status
is `zn_preview_start`/preview, one human, no editor participant or survivor;
the preceding cell-review survivor baseline matches. Ask for the new controls'
human review and selection of the first saved world prefab before exporting
or arranging its bounded real-cell test. Preserve normal-world scale blocks
and the ground-shadow deferral; no map rebuild or world refresh is needed.
During the new UI review the user reported `(20,0,0)` did not move the grid.
Source now translates grid and compass XY with the prefab-preview offset,
preserving reference geometry and the approved reference-surface guide height.
Editor53/53 and GLua376/0 pass, but this correction is not yet live-loaded.
Current state supersedes the launcher note above: `gm_flatgrass`/preview,
one editor owner, no survivor. Preserve all tabs; prefer the existing
snapshot-preserving Change Map flow, or confirm saved work before a reload.
The next check is visible grid movement for X20, then world-prefab selection
and explicit export. Do not mistake source tests for that human review.
The user then changed maps and confirmed the grid moves correctly. Current
status is `gm_construct`/preview with one owner and no survivor. They chose
`test123`, but the saved DATA document has no world placement and a movable
bench scaled1.4; only dry-run export ran. Keep the saved document unchanged
and obtain an enabled unscaled world prefab or an explicit scaling decision.
An exporter prefab/prop-ID variable collision is fixed; export67 passes.

The metadata/save regression is corrected: explicit form docking order,
focused-entry-safe refresh and opened-tab-bound saved IDs pass editor55,
explorer10, transfer2, map-contract2 and GLua376/0. The user confirmed the
layout and saving. The saved unscaled `test` stool was verified and explicitly
exported at preview logical `(4,-11)`, tile `(0,0)`, offset `(0,1,0)`, loot Off.
Launcher return cleared all editor/transfer markers and matched the stored
survivor baseline. On a user-approved deployed visit, normal spawning produced
one `world_test` anchor/one stool; the user confirmed placement and collision.
Normal travel then restored the starting preview cell `(14,0)`/cell302 on
`zz_preview_ed3d3fa48090-cp`, with zero prefab instances and health100.
City data and preview attributes were unchanged; only normal survival ticks
and save bookkeeping changed during gameplay. The export remains enabled.
An approved follow-up confirmed same-BSP logical control `(7,-9)`/cell79
has no prefab while revisiting `(4,-11)`/cell28 spawns one `world_test`.
Both loads used `zz_preview_d56e6ff2981a` with `(14,0)` as an intermediate;
direct same-BSP gate travel was not tested. The survivor returned to `(14,0)`
alive at health100. Stable data matched; normal transitions replenished
stamina. Multiplayer, scaled spawning and other A2 items remain open.
No world refresh or map rebuild ran.
The installed preview has no accessible adjacent same-BSP cell pair. The
transition fixture models the existing asynchronous Walker preload and
confirms forced same-map gate reloads; fresh `zn_test_safezones`27/27 and
GLua376/0 pass. This does not claim a direct live same-BSP gate traversal.
The isolated launcher scale suite now includes the `test123` bench at 1x
and 1.4x, all axes and both motion settings, without changing that document.
Offline matrix/tolerance/cleanup/launcher-guard checks and GLua376/0 pass;
after a consented launcher return, native `zn_test_prefab_spawn` passed 7/7,
the saved return cell remained `(14,0)`, and `test123` retained its hash.
A separately gated `-ScaledBench` isolated fixture is prepared for matched
client/server traces of five 1.4x movable benches. Owner18/18, focused
trace/scale tests, staging23/23 and GLua376/0 pass. The user approved staging
and confirmed bench size, walking and pushing. Matching client/server traces
before and after interaction differed by at most0.018 units. The player
returned to the launcher; saved cell, persistence and user prefab checks
passed, and the hash-ledger files are absent. Normal scaled spawning remains
blocked; actual PVS re-entry, multiplayer and deployed collision are untested.
The existing isolated editor guard preview now accepts validated combat
overrides and uses a non-player-targeting Walker with a15-second expiry.
Offline probe3/3, config2/2, actor5/5, targeting2/2 and GLua376/0 pass;
fresh prefab28/28, loot13/13 and loot-spots30/30 pass. The override firing
check ran in `gm_flatgrass`/preview with one owner and no survivor: a pistol
at damage23/interval0.2/spread0 fired12 shots in2.55s for276 health loss.
Expiry removed the guard, weapon and Walker; a separate check reported zero.
City/preview attributes and saved cell `(14,0)` match the baseline. The
user returned to the launcher, with no editor or survivor loaded and no
session marker. Actual guard kills/rewards and multiplayer remain open; no
world work is authorized.
**Guard testing deferred (user, 2026-10-30):** guards will not be used until
later, so skip further guard verification to progress faster. The live
kill/corpse-reward probe never reached `OnKilled`; leave it unverified and do
not claim guard kills, rewards, deployed guards or multiplayer guard
behavior. Preserve guard source and `testguard`; resume only when needed.
**A2 accepted with limits (user, 2026-10-30); Phase B (zombie AI) is now
active.** Unverified limits retained: multiplayer, normal-world scaling
(blocked), real-cell gate/roadblock set piece, real-cell prefab loot accept
and guard runtime. Do not claim them.
**Phase B implemented and accepted with limits (2026-10-30):**
behaviour decisions and implementation are recorded in the tracker's Phase B
section and in `docs/walker_simulation.md`. A new `ZM_WalkerAwareness`
module handles camera PVS, visibility, noise and alerts, and the despawn
paths now honour camera visibility. The user's live review drove fixes for
static re-pathing lag, ground spawns, in-view despawns, sky launches
(airborne safety net only; cause unproven), a 0.9 s wind-up, prop/crowd
sidestep/yield/hold recovery (walkers stay solid) and a radiated-glow fade.
Walker fixtures 12/12 and GLua 378/0 pass; the user reports lag better, no
ground spawns/visible despawns/sky launches and movement good enough for
now; the radiated glow fades in smoothly. A ticket-seed clustering bug that
left whole walker batches all or never radiated (0/100 in cell 302) now uses
a murmur3-mixed seed; live 36/100 radiated. Measured performance and
multiplayer remain unverified. **Phase B accepted with these limits (user,
2026-10-30). Phase C is also accepted with the limits below; Phase D is
active.** Decisions and review evidence are recorded in the tracker.

The user requested a Change Map button beside Return to Launcher in the
prefab editor, with recommended `gm_construct`/`gm_flatgrass` thumbnails and
custom-map selection. Restore every open tab, including unsaved edits, across
the reload; show mounted custom maps separately with missing-thumbnail
placeholders. They
also requested a directly placeable Hammer guard with clothing and other
agreed guard settings available in Hammer and the prefab editor, including
per-guard damage, fire rate and accuracy. Guards remain invulnerable with
unlimited ammo. Preserve
the preview-only session, existing guard decisions and separate output gates.
The direct `zn_prefab_guard` Hammer definition and shared combat overrides
are source-wired; blank overrides retain weapon defaults, firing interval is
seconds per shot (minimum 0.05), and lower shot spread means greater accuracy.
Offline prefab40/40, guard9/9, export44, packaging69 and GLua367/0 pass.
Fresh preview-launcher prefab24/24, guard configuration1/1 and weapon
registry1/1 pass; the session marker is absent and survivor persistence
matches the baseline. A separately approved isolated compiled fixture passed
VBSP/VVIS/VRAD, 4 clusters/4 portals, 33 source/BSP assertions and live guard
fixture1/1. The user confirmed default/custom guards, clothing and weapons
look correct. After returning to the launcher, the marker was absent, the
survivor baseline matched and all temporary fixture files were removed.
Actual firing of the overrides and deployed-world/multiplayer behavior remain
unverified.
Normal guard spawning and export are now source-wired after the isolated
guard-anchor fixture and its user visual review passed; do not infer A2 or
deployed-world acceptance from that fixture.
Guard editor and explorer authoring/preview now exist in source, using
server-supplied weapon choices and the existing shared-budget clothing queue.
Offline prefab41/41, editor46/46, session16/16, guard preview3/3, export44,
packaging69 and GLua370/0 pass. After a safe preview-launcher reload, live prefab25/25 and guard
configuration1/1 pass. The user confirmed the editor controls and explorer
preview work and saved a one-guard `testguard` document, independently
verified in server DATA; preserve it. The editor remains open on
`gm_flatgrass`/preview with one owner and no survivor loaded. Ask before a
reload or discard and verify launcher return/baseline after the session. The map picker and automatic unsaved-tab recovery are now implemented in
source, but need the fresh-client and actual map-transition checks recorded
below.
The user confirmed all three guard combat overrides stay checked after
save/reopen, and a subsequent DATA read confirms the three fields exist.
An earlier snapshot preceded that saved state; do not treat it as a save bug.
Guard spawning reports deferred readiness, applies anchor transforms and
rolls back on initialization failure. An in-memory live fixture was prepared for the
preview launcher, checking four rotations and cleanup without a survivor.
Offline guard11/11 and GLua371/0 pass. The user saved and returned; separate
status and persistence checks confirmed the launcher, absent editor marker,
no loaded survivor and matching baseline. After a fresh reload, the live
fixture started1/1, checked four guard rotations/readiness/overrides1/1 and
verified post-frame cleanup1/1. Preserve `testguard`; actual firing, normal
actual deployed anchor integration, multiplayer and world behavior remain unverified.
The fixture-only prefab owner now waits for all deferred guards before loot,
rolls back failures and ignores callbacks from removed anchors or old maps.
Offline owner15/15 and spawn9/9 pass; fresh live prefab25/25, existing
spawn6/6 and loot-spot30/30 pass, but the pending-guard owner path has not
run through a compiled anchor. One packaged static guard weapon catalogue
serves both server and export validation; live catalogue1/1 and config1/1
pass. The user then approved a separate four-anchor fixture: compiled
source/BSP15, VBSP/VVIS/VRAD and 4 clusters/4 portals pass; live owner and
guard-anchor suite1/1 show four ready guards and four props, and the user
confirmed placement, rotations and clothing. Return, marker and survivor
baseline checks passed; ledger-owned assets and generated fixture were
removed. Normal guard spawning and export are now source-wired; prefab43/43,
export57, GLua371/0 and a non-writing `testguard` export dry run pass.
The normal-path wiring and pending-report fix are not yet fresh-loaded.
Actual city-cell eligibility, overridden firing, kills/rewards, multiplayer
and lifecycle remain unverified.
The map picker uses recommended/custom mounted-map pages and a verified local
tab snapshot plus an owner-bound server marker. Offline map contract2/2,
transfer2/2, editor48/48, session20/20, prefab46/46, packaging70 and
GLua376/0 pass. It has not been live-loaded: check actual thumbnail materials,
JSON/DATA round-trip, switching between `gm_flatgrass` and `gm_construct`,
dirty-tab restoration, UI appearance and custom-map behavior before acceptance.
The first live `gm_construct` switch was safely rejected because the world
index returns `nil` for no match; source and fixtures now accept that
documented owner behavior while rejecting malformed results. The editor is
still open on `gm_flatgrass`/preview, one owner, no survivor; the rejected
transfer file is absent. Prefab contract runner35/35 and GLua376/0 pass.
Ask before reloading or discarding the user's test tabs, then retry the switch.
The user saved and approved the reload, then retried. Separate status now
confirms `gm_construct`/preview, one owner and no survivor, with a valid
workspace; the marker has no pending transfer and the local snapshot is
absent. The user confirmed both unsaved tabs and edits restored. The editor
remains open; verify reverse switching and saved-tab authorization before
returning and comparing the survivor baseline. Do not reload or discard work
without consent.
The user then confirmed the reverse `gm_construct` to `gm_flatgrass` switch
retained all tabs and an unsaved `testguard` edit. Separate status confirms
the saved-tab authorization, absent transfer snapshot, one owner and no
survivor; the saved `testguard` file is hash-unchanged. The user confirmed browser thumbnails, the Custom Maps tab and search. They
returned to the preview launcher; separate checks show no editor owner or
loaded survivor, no editor/transfer marker, unchanged saved `testguard` and
matching city/preview persistence. An actual custom-map transition remains
unverified.
The user now requests a Cells tab in Change Map and tile X/Y controls in the
left View/camera area for previewing a prefab on a cell. Default the editor
to the cell centre, on the crossroads/T/straight road centre piece. Settle
the tile range and workspace movement semantics first: the user chose the
central 5x5 tiles at centred offsets `-2..2`, east +X/north +Y, and moving
the entire preview workspace onto the detected surface without changing
saved coordinates. Preserve
preview-only and survivor isolation; do not regenerate or change production
worlds.
The cell-preview source now resolves preview cells through `ZM_World`, uses
the centre surface by default and offers global workspace tile offsets
`-2..2`. Same-BSP cells retain separate logical identities and reload; failed
switch recovery restores the prior cell/tile. Offline editor/cell and session
fixtures pass, as do prefab contract runner35/35 and GLua376/0. The source is
not yet live-loaded. First review the existing preview crossroads cell
logical `(14,0)`, ID302, map `zz_preview_ed3d3fa48090-cp`; check its engine
mount before attempting entry. Do not regenerate or stage a world.
The user instead selected existing preview cell `(17,-11)`, ID41, motorway
straight map `zz_preview_fec25b5a01e6`. They confirmed the centre placement
looks correct; separate status reports tile `(0,0)`, origin
`(0,0,64.03125)`, one owner and no survivor. The `(14,0)` crossroads has not
been reviewed. Test tile movement with the editor open, preserving user work.
The user approved workspace/prefab placement after tile movement on this
motorway cell. Separate marker/status checks verify X=-1 at -640, X=1 at
+640, and Y=1 at +640, with detected heights 68.03125/68.03125/64.03125.
The first positive-X request initially selected -1; the later +1 check is
independently verified. The editor remains open and no survivor is loaded.
The user then confirmed the `(14,0)` crossroads and preserved tabs.
Independent status verifies cell302, `zz_preview_ed3d3fa48090-cp`, centre
tile `(0,0)`, origin `(0,0,36.03125)`, one owner, no survivor and no pending
transfer/snapshot. These are bounded checks, not all-cell/25-tile coverage.
Ask before returning; verify the marker and survivor baseline afterward.

**User deferral, 2026-10-29:** stop investigating missing editable-prefab
ground shadows and defer the issue until the end of Alpha 3.3. Continue other
approved work without treating spotlight visuals, replication or visibility
selection as accepted. Do not reopen this investigation early.

**Alpha 3.3 implementation is authorized; A1/A2/A3, B and C are accepted
with limits and D is active:** follow the
[Alpha 3.3 phased plan](todo-alpha.3.3.md). The prefab editor and explorer are
the top priority, zombie AI is medium priority, fog is the least-priority
presentation work, and world-generation rules are last. The order of other
features is a proposal, not user-approved priority. Settle each phase's open
behavior decisions first; preserve the separate expensive-work gates.
Phase C attribute and armour implementation and its transactional migration
are source-wired. Live inventory52/52 and weapon-effects24/24 include the
new equip/persistence and firearm-calculation cases; the user approved the
scoreboard/inventory presentation and said temporary armour and a pistol
worked and felt fine. Movement penalties were measured, but real damage and
ordinary firing/reloading remain unverified. The identified test items were
removed; a bandage stack that appeared during the review was left intact.
The saved preview infinite-ammo toggle was enabled during the 64/9 clip
sample; its engine-max top-up is consistent with the sample, but the live
flag was not measured. This does not prove a normal-weapon fault. Do not
change the user's cheats. The user accepted Phase C with those and
multiplayer limits; detailed guard testing remains deferred.
The world-map star's incomplete triangle initialization is corrected in
source; focused world-map4/4 and GLua380/0 pass. After an approved same-map
reload, the survivor's cell, attributes and inventory matched the pre-reload
snapshot; the user confirmed that the scrolling stars look correct and the
error does not return.
The user next requested AFK protection for the world map and chose the
existing three-second menu countdown, interruption and exit grace. Source
routes M, the Tab menu and `zombiesim_map` through the server-owned AFK
service and handles rapid cancel/reopen. Offline world-map/AFK13/13,
GLua380/0 and fresh isolated in-game AFK14/14 pass. After an approved
reload, the survivor's cell, attributes and inventory matched; the user
confirmed M cancellation, an eight-second open-map AFK hold, M/X close
and grace, restored controls, the Tab map entry and rapid reopening.
Real survivor damage interruption, firing during grace, the console entry
and multiplayer remain unverified live. Continue Phase D.
The Phase D profession selector is source-wired: an icon grid and selected
job details show placeholder backstory, services, delivery tiers and all
attribute bonuses; narrow layouts stack without changing the saved draft.
Offline picker7/7, missing-icon handling, launcher Cell Health2/2 and
GLua382/0 pass. After a user-approved preview-launcher reload, the actual-client
presentation suite passed23/23, and city/preview persistence, inventory,
stash, implants and character slots matched the pre-reload baseline. No
survivor is loaded or was created. Human review of the wizard using an empty
slot found the attribute table extending outside its detail box. Source now
expands that box to contain its text and rows and uses the page scrollbar;
offline picker8/8 and GLua382/0 pass. After the user cancelled the draft and
approved a launcher reload, fresh-client presentation24/24 passed, including
detail bounds at four widths. City/preview persistence, inventory, stash,
implants and slots match the baseline; no survivor is loaded. The user says
the revised screen looks good and wants more noticeable profession bonuses,
including Police shotgun/pistol/rifle proficiency and a more rounded Army.
They chose a 10-point maximum for new survivors only, left Civilian and
Capitalist's existing behavior unchanged, and want positive bonuses
emphasized. Existing survivors retain their original bonus rules after job
changes; the user delegated the other role-appropriate allocations. Some
attributes have no gameplay effects yet. Capitalist's existing
`playerLootBonuses` field is ignored by the static-data loader; do not claim
that its cash bonus currently works.
Source now stores legacy/current profession-bonus rules per survivor, retaining
the chosen rules through job changes and refreshing dependent effects. Existing
character rows default to legacy; new characters use current rules. Offline
balance/persistence9/9, picker6/6 plus shared cases8/8, GLua382/0 and diff
checks pass. After a user-approved launcher reload, both existing characters
received legacy version1; 16 survivor-related tables match the verified
pre-reload SQLite backup before and after the test suites. Live static20/20,
professions14/14, characters13/13, mastercraft9/9, weapon effects24/24 and
movement6/6 pass. Native hydration/snapshot cases use fake players/networking;
deployed and multiplayer replication remain unverified. Fresh client
profession cases pass; an earlier 23/24 result failed its Home Earth input
case before Home readiness was established. After the camera reload below,
the confirmed-Home client suite passes25/25, including that case. The user
confirmed the new bonus highlighting looks good without saving a survivor.
The user added the preview launcher's `create_character` point camera and
requested the same marker in the city launcher; a room will be authored later.
City source now has the same initial pose. Server/client camera transport,
creation/legacy-appearance view selection, PVS, credit priority and a warned
fallback for old BSPs are source-wired. Launcher fixtures pass15/15 including
eight camera cases; parity checks both source markers and the compiled
preview camera. The user approved the preview-only compile/stage/reload:
VBSP/VVIS/VRAD pass, both staged preview BSPs hash `BFF1D6689B9AAF7060676D87217DE0AF4CDBDB791B17361D517A39874976502E`,
and previous preview BSP copies are hash-backed in session files. Fresh
client status received the authored camera within0.04 units/degrees and
confirmed ready Home after the25/25 client suite. City/preview survivor
persistence matched before and after reload/tests. The user confirmed the
preview creation view and Back/Cancel navigation look good; separate
post-review status shows ready Home, no survivor loaded and matching
city/preview persistence. Actual legacy appearance and pending-save
navigation remain unverified live. The user separately approved the city
launcher build/stage and temporary review. VBSP/VVIS/VRAD and compiled-camera
checks pass; both staged city BSPs hash `D25AB5A6F489AA8BA8FCC8419D3A49814FCC160264F0AD8B1E44B0F555A58639`
and previous copies are hash-backed in session files. The user confirmed
city creation view and Back/Cancel; a fresh user-run status verifies the
received pose within0.04 units/degrees and ready Home. The approved return
is complete: separate status confirms ready `zn_preview_start`/preview, no
survivor, restored selected profile and city/preview persistence matching
the pre-visit snapshot. No room or cell map changed.
Phase D calling-card artist decisions: `_background.png`/`_details.png`
classify finished PNGs; unclassified files must be referenced ingredients or
reported. Preserve original bytes/transparency for any 6:1 finished PNG and
generate750x125 cards from ordered cover/repeat layers with colour, opacity,
scale, spacing and position. Use stable category/name IDs and explicit rename
aliases; removed selections fall back to defaults without losing ownership.
The first-review ceiling is512 generated designs, not silent truncation.
At this decision point artist source had no PNGs; temporary original fixtures
were not approved staged artwork. The supplied ingredients and current D2
status are recorded at the top of this guide.
The D1 source pipeline was implemented and documented in
`docs/calling-card-artist-workflow.md`; at that checkpoint the installed
catalogue contained only the two unchanged defaults. Calling-card fixtures73/73,
Workshop packaging73/73, Phase D offline integration20/20 and GLua383/0 passed.
Ownership, selection and later staging are recorded above. After the user confirmed
the draft safe and approved a preview-launcher reload, native static-data
fixtures pass22/22, validation reports zero errors and two cards, and the fresh
client launcher suite passes25/25. A separate client status confirms Home;
no survivor is loaded, city/preview data and slots match before/after, and
19 survivor/related SQLite table digests match. The existing Capitalist warning
remains. Real handcrafted/generated scoreboard review remains open.
The user brought A3 editor UI refinement forward after the bounded particle
slice, when A2 was still incomplete. Use top-left Prefab,
Place and Scene buttons with one left panel at a time, initially closed; keep
the right inspector in place, allow much closer zoom, and match the game's
existing visual style. The editable-prop shadow investigation remains deferred.
The user also requested Cell Health in the launcher Tools sidebar. Source
opens the existing preview-admin manager and restores Tools focus on close;
no batch starts on opening and server deployment guards remain unchanged.
Offline launcher2/2, Cell Health6/6 and GLua352/0 pass. Fresh launcher and
human interaction review remain pending.
The first A3 source pass adds initially closed, mutually exclusive
Prefab/Place/Scene panels using the game skin, keeps the right inspector,
lowers the zoom minimum to64 and replaces the loot-group text field with a
sorted registry selector and Model default. Offline editor36/36,
session13/13, explorer7/7, launcher2/2, Cell Health6/6 and GLua352/0 pass.
Fresh-load interaction, resolution and visual review remain open.
The user expanded A3 to include a context-aware right inspector, compact
X/Y/Z position and rotation rows, separate camera/grid controls, prefab
explorer UI refinement and multiple simultaneously open prefab document
tabs along the top. Frame padding has been removed in source but not yet
live-loaded; preserve all saved prefabs.
The user chose one tab per saved prefab (reopening focuses it), independent
unsaved documents and per-tab view/preview state, Save/Discard/Cancel on dirty
close, and a new blank tab after closing the last. A combined View panel owns
camera and grid controls: zoom, yaw/pitch, reset, Shift+right-drag pan,
grid/compass visibility, grid spacing and snap settings. Keep the 640-unit
guide and existing right-drag orbit/middle-click reset.
The user additionally chose a per-tab, preview-only reference-tile height
offset. It moves only the reference tile; prefab objects and saved/world
placement must remain unchanged.
Multi-tab source tracks all server-authorized open IDs, correlates
asynchronous requests to their tabs, restores per-tab document/preview state,
and protects dirty tabs and pending loads during exit. The View panel,
preview-only reference offset, selection-aware inspector with compact axis
rows, and themed explorer are implemented. The full offline prefab runner
passes31/31, including editor44/44, session14/14 and explorer8/8;
GLua352/0, launcher Cell Health2/2 and Cell Health contract6/6 pass.
Live acceptance remains open. A read-only status confirms the editor on
`gm_flatgrass`/preview with one owner and no survivor loaded; obtain consent
before a reload or discarding unsaved work.
The user confirmed their work was saved and approved the reload; a fresh
status again confirms the same map/profile, sole owner and no survivor.
A local capture shows the new toolbar, tabs and empty inspector. The console
log is stale, and human interaction/visual review remains pending; preserve
the user's saved prefabs.
The user gave a positive overall editor review and requested a separate Scene
height offset for the whole prefab. They selected preview-only behavior:
props, selection, light and particle previews move together, while saved
coordinates, world placement and the reference remain unchanged. The offset
is per-tab. Offline editor45/45, light preview1/1, particle preview4/4 and
GLua352/0 pass. After a user-approved reload, the user confirmed the new
control works; live `zn_test_prefabs` passes23/23. The user returned through
the editor UI; separate status confirms `zn_preview_start`/preview with no
editor participant or loaded survivor, the marker is absent and the stored
city/preview persistence hash matches the baseline. Formal A3 acceptance
and any unreviewed resolution/close-path limits remain separate. The user
subsequently accepted A3 with those limits; resume A2 without reopening the
deferred editable-prop ground-shadow investigation.
For A2 guards, the user chose stationary, named, non-interactive,
invulnerable guards that zombies do not target, with selectable compatible
weapons, editable engagement range, no fixed guard cap but a performance
warning, and a chosen idle animation interrupted during combat and resumed
afterward. Use clothing-compatible citizen models, not rebel catalogue
clothing; verify real engine compatibility before promising supported assets.
Start weapons with a small verified subset. Guards turn toward targets then
return to their authored facing, cannot harm survivors or friendly NPCs,
and their zombie kills can produce loot without awarding player XP. Existing
enemy rewards require a player killer, so wire a guard-specific loot path.
Use normal enemy drop chances and interpolate guard-kill item levels across
each item's allowed range by danger, without player bonuses; preserve the
separate guaranteed maximum-level boss reward. The user chose unlimited guard
ammunition after being told about unattended farming.
The guard-kill reward foundation is implemented but no guard entity is wired:
offline guard-reward3/3 and GLua353/0 pass, as do fresh preview live loot13/13,
enemies14/14 and bosses6/6. Stored survivor persistence remains at baseline.
Actual guard spawning, combat, clothing and editor authoring are not verified.
The bounded engine model probe now passes1/1, and its separate post-frame
cleanup check passes1/1 after fixing an invalid same-frame removal assertion.
The clothing-compatible male_03 model reports idle index2, right-hand bone11,
attachment5, and pistol/SMG idle and range sequence names. This is metadata,
not visible animation, attachment, clothing or combat evidence; GLua354/0.
An isolated, nonlethal guard-shot feasibility probe is prepared. It requires
the sole-human editor workspace, blocks damage to other entities and removes
both temporary entities; cleanup is checked separately after the frame.
Offline safety/cleanup fixtures and GLua355/0 pass, and the launcher correctly
rejects it. Ask the user to open the editor before the live probe.
The user opened the editor; separate status confirmed the sole preview owner
and no survivor. Live nonlethal shot1/1 and post-frame cleanup1/1 pass.
This does not prove real guard presentation, player friendly-fire safety or
multiplayer. The editor remains open; protect any unsaved work on reload.
The new guard-targeting primitive selects the nearest visible living Walker
or boss within range and filters damage to that selected target. The shot
probe now exercises it. Offline targeting2/2, rewards3/3, probe safety and
GLua357/0 pass; fresh in-engine verification awaits consent to reload the
current editor.
After a user-approved reload, the real targeting primitive's nonlethal engine
shot passes1/1 and post-frame cleanup1/1; separate status confirms the
sole-owner/no-survivor editor workspace. Target selection and friendly-fire
filtering remain offline-fixture evidence; guard entity/authoring remain open.
An initial guard actor and owner-only editor preview now exist in source; the
preview owns a high-health temporary Walker and cleans up on stop, disconnect,
map cleanup or expiry. Offline actor3/3, config1/1, weapon1/1, targeting2/2,
reward3/3, probe2/2, clothing queue1/1, GLua367/0 and packaging fixtures69
pass. The actor, clothing, weapon placement and animations have not been
live-loaded or visually accepted, and normal prefab authoring/spawning is
not wired. Obtain consent before reloading the current editor.
After a user-approved reload, the engine resolved both candidate weapons and
the isolated guard fired at the high-health Walker. The user reported
outstretched/T-pose arms while shooting. The Walker was intentionally
nonlethal for the preview. Guard, Walker and weapon cleanup was independently
verified; the editor remains open. Test a firing gesture layered over the
weapon idle rather than resetting the firing sequence as the whole-body pose.
Source now layers and reuses the firing gesture over the weapon idle and
removes it on combat exit; focused guard fixtures and GLua367/0 pass. This
is a candidate correction only, not a visually verified animation fix.
After a fresh user-approved reload, the guard fired with a live gesture layer;
the user reported the gun faces the wrong way and did not explicitly accept
the body pose. The preview was stopped and zero owned entities remained.
Preview-only orientation controls and muzzle diagnostics now pass focused
fixtures and GLua367/0; reload with consent before the next check.
The user clarified that the barrel pointed backward. Temporary local yaw180
corrected the barrel direction, but the grip still does not fit the hand;
the body pose has not been explicitly accepted. The preview is stopped and
cleanup verified. Test the documented bone-merge attachment before committing
an offset; do not treat muzzle-position alignment as visual proof.
The owner-only bone-merge comparison is prepared and restores its previous
attachment transform when disabled. Focused guard fixtures and GLua367/0
pass; it needs a consented fresh reload and human hand/weapon review.
After that reload the user confirmed the bone-merged pistol's hand placement,
direction and arm pose. Source now uses bone merge for guard weapons; focused
fixtures and GLua367/0 pass, and the pistol comparison was stopped with zero
owned entities remaining. The source change and SMG visual remain unverified;
normal prefab authoring/spawning is still open.
After a user-approved reload, the source-backed pistol preview was visually
confirmed. The user also confirmed the SMG weapon, pose and sound, but two
SMG status samples showed `firingGesture=false` while shots increased; retain
that diagnostic limit. Both previews were stopped and their owned entities
were confirmed absent. Guard authoring, world spawning, real kill/reward,
multiplayer and friendly-fire checks remain open; the editor is still open.
Guard record schema and server content validation are now source-wired, with
legacy documents retaining an empty guard list. Nonempty guard exports and
world spawns explicitly refuse until integration is ready. Offline prefab
runner31/31, guard fixtures9/9, export44 and GLua367/0 pass; the schema is
not yet live-loaded and guard editor controls remain absent.
Fresh actual-client launcher Tools8/8 passes; the user confirmed Cell Health
opens with unchecked categories and closes back to Tools, without starting a
batch. Editor screenshot capture now includes VGUI (focused case and
GLua352/0 pass). The preview launcher is loaded with no survivor; open the
editor for human A3 review.
The initial editor capture exposed bright default list backgrounds and unused
frame title padding. Source now uses the existing dark/red palette for editor
lists and removes that padding; focused editor36/36, explorer7/7 and
GLua352/0 pass. The styling fix needs a fresh editor reload; ask before
discarding any unsaved work and obtain a new human review.
The user approved the initial prefab editor as a preview-launcher admin tool
requiring no other connected humans, saving to server DATA with explicit addon
export, and using 3D mouse gizmos plus numeric controls. Keep survivor state
untouched and verify return to the preview launcher.
An initial editor source prototype is in progress; focused offline fixtures
pass 21 cases, export13, packaging68 and GLua295/0. GMod runs with
`-disableluarefresh` on `zn_preview_start`/preview, and a connected admin was
confirmed by a read-only slot probe before a same-map reload. `zn_test_prefabs`
timed out without acknowledgement or a report while the server continued
ticking; a separate slot probe still passed. The user reported a nil test
factory caused by relative nested includes; dependencies are now injected from
`gamemode/init.lua`, with an 11/11 offline registration fixture. A fresh
preview-launcher reload and `zn_test_prefabs` pass 11/11. Ask the user to
open the editor for the two-prop visual/interaction review, then compare the
stored city/preview persistence baseline hash recorded in the tracker. The
first live attempt reached `gm_flatgrass` but its trace missed ground at
Z -12288 and exposed a danger-star HUD error. Source fixes and focused
fixtures pass. The player returned to `zn_preview_start`/preview, the session
marker is absent, and stored city/preview data matches the pre-editor baseline.
Reload the current launcher and retry the editor before continuing.
The 2026-10-28 continuation reopened the editor successfully; workspace status
is `gm_flatgrass`/preview with one owner and no survivor loaded. The user
confirmed prop placement and gizmo interaction. A valid-ID save failure was
traced to text-field synchronization; the fix passed focused checks and was
live-verified with the user's one-prop `test` prefab. The user requested a
larger model thumbnail browser, a ground compass, many selectable authored
tile references and possible fog/light controls. Browser/compass fixtures
pass; the user confirmed both work and accepts the browser for now, with visual
polish deferred to a separate Phase A3. The user approved an editor-only
simulated bright/dark screen grade and inner-city fog preview. Preserve the
user's saved `test` prefab; after this session return to the preview launcher
and compare the recorded survivor baseline. One approved straight-road model
was compiled and 18 temporary files staged with a hash ledger at
`generated/prefab_road_reference_20261028/staging-ledger.json`; no map was
rebuilt. The reference selector and atmosphere controls have passing focused
fixtures but need a fresh-load human review before broader tile generation.
The road extractor omits bottom faces and is not yet a general tile converter.
After fresh reload, the user confirmed the prototype road is textured and
aligned, both preview controls work, and No reference removes the road.
They want the later A3 UI phase to organize editor workflows into top-level
areas (starting with a top-left Prefab button and side panel), because the
reference selector was hard to find. Do not redesign the UI in the current
slice. The user saved and reopened a two-prop `test123` prefab, returned to
`zn_preview_start`/preview, and the marker was absent and survivor baseline
matched. They requested double-click mode cycling and chose bounded uniform
scale first. Live mode cycling worked, but the prop did not visually scale
and the handles did not identify modes. Source now uses a render-scale matrix
and distinct arrow/ring/square handles; focused fixtures pass, and the player
returned to the preview launcher with the survivor baseline unchanged.
Reload and repeat the actual scale/handle review. Preserve user prefabs;
independent-axis stretching stays deferred until collision support is designed
and validated.
The user subsequently confirmed visible scale and saved size restoration,
but reported rotation rings were unintuitive. Source now tracks mouse
movement on the selected ring plane with signed angle/wrap handling and
orientation-aware axes; focused fixtures and GLua295/0 pass. The current
editor session must be checked before any reload. Visually test rotation with
snapping on/off and an orbited camera; do not infer acceptance from the
offline fixtures.
The user revised the ring interaction: single-click a ring to select it,
then hold left and drag anywhere in the viewport. Release retains selection;
a click elsewhere without dragging deselects it, and right-click during a drag
cancels that drag. Focused client fixtures pass 24/24, atmosphere18/18 and
GLua295/0. With save confirmation, the editor was reloaded on
`gm_flatgrass`/preview; separate status confirmed one owner and no loaded
survivor state. The user confirmed the new selection/drag/deselection,
crossings, snapping, camera orbit, middle-click reset and prop mode cycling.
After return to `zn_preview_start`/preview, a separate status check confirmed
the editor session closed, its marker was absent and no survivor was loaded;
the stored city/preview persistence hash matched the pre-editor baseline.
The user also requested middle-click reset to default rotation. Source and
focused fixtures now reset only the clicked prop's rotation, preserving its
position/scale and releasing its selected ring; the user confirmed it works.
The user chose a separate prefab explorer accessible from launcher and editor,
with interactive 3D previews, duplicate display names and stable unique IDs,
and a server-shared library manageable by authorized preview admins. Source
now implements those entry points, search/tag filtering, preview and confirmed
rename/delete; managing the document currently open in the editor requires
closing it there first. The user confirmed the launcher preview, search,
orbit/zoom and close behavior, then found **Open in Editor** missing there.
Source now carries the validated selected ID into the editor session.
Offline explorer6/6, editor24/24, session10/10, packaging68/68 and
GLua297/0 pass. The user confirmed the launcher-to-editor transition and
editor explorer work, and confirmed rename/delete/filtering using a disposable
prefab. On return to `zn_preview_start`/preview the editor marker was absent,
no survivor loaded and stored city/preview persistence matched the baseline.
The user also requested much closer editor zoom and possible camera controls
in the deferred A3 UI phase; do not implement those in this slice.
The live `zn_test_prefabs` suite now passes 15/15 after a launcher reload,
including real engine JSON/storage precision and four cardinal local yaw
values in in-memory fixtures. World-anchor rotations, overlapping spawned
prefabs and scaled gameplay collision remain A2 work. The user accepted A1
with those limits and approved proceeding to A2.
A2 decisions: normal spawning reads explicitly exported addon prefabs, not
DATA overrides; multiple requested tags must all match; explicitly guaranteed
lootable props bypass both the activation roll and 320-unit spacing. Ordinary
loot remains unchanged. World regeneration and gate-access changes remain
separately gated.
The user chose per-prop stationary/movable behavior; new and legacy props
default to stationary. Source now includes the editor setting, contract,
storage and export validation; focused editor25/25, storage7/7, contract6/6,
export23 and GLua299/0 pass. A fresh preview launch passed live
`zn_test_prefabs` 17/17. The user confirmed the new control works per prop
and persists on save/reopen. After return to the preview launcher, a
connected-admin status confirmed no editor session or survivor loaded; the
marker was absent and stored city/preview persistence matched the baseline.
The user chose resetting moved props to their authored placement on cell
load rather than persisting their moved positions.
World physics and scaled collision still require implementation and live
validation.
An initial server-side exported catalog and deterministic all-tag selector
exist, with offline catalog2/2 and GLua299/0. They are not yet wired to a
runtime spawner or Hammer entity; no generated world or exported prefab changed.
The unscaled spawn primitive now has offline spawn2/2 and GLua302/0.
Fresh `zn_test_prefab_spawn` passes 1/1 in the preview launcher, checking
four cardinal anchor transforms and stationary/movable native physics flags
with transient entities removed by fixture cleanup. This is not sustained
physics, collision-trace or visual verification. Scale other than 1 remains
explicitly blocked. Normal map spawning is not wired yet; the next Hammer
anchor needs the existing custom-point instance-transform handling, plus
explicit permission for generator source changes and a bounded compile.
The user then approved that narrow source change and one isolated compile,
but not staging or entering it. The Hammer `zn_prefab_anchor`, FGD, existing
custom-point instance emitter and `sv_prefabs.lua` runtime owner are wired.
Tile-local anchors explicitly set `instance_local=1`; runtime ignores raw
copies while preserving direct map anchors. Offline owner6/6, spawn2/2,
packaging68/68 and GLua306/0 pass. The corrected isolated fixture in
`generated/prefab_anchor_20261029` passes VBSP/VVIS/VRAD, 4 clusters/4 portals
and 27 compiled-anchor assertions. Two earlier successful VBSP exits omitted
instances due to fixture paths; only the corrected relative-path build is
valid evidence. No authored tiles or staged worlds changed. Actual runtime
anchor/physics/visual review, scaled collision, loot and gate content remain
pending; do not claim A2 acceptance.
The next collision probe passed actual server traces for an oil drum at
scales0.1/0.5/1/2/10 on all three axes, stationary and movable, within
5% or0.5 units versus the unscaled control; `zn_test_prefab_spawn`2/2.
This does not validate client traces or gameplay/visual collision, so scaled
world spawning remains blocked. Fixed early `PlayerSpawn` ordering so loot
waits for prefab initialization and resumes even on a reported prefab
failure. Offline prefab runner12/12, runtime owner7/7 and GLua306/0 pass;
fresh launcher `zn_test_loot_spots`19/19 and spawn2/2 pass. Actual city-cell
ordering and visual anchor review remain open.
The user approved staging and entering the one isolated anchor fixture
without loading a survivor. Source reuses the sole-human editor marker and
a guarded synthetic-cell command; offline session11/11, owner8/8, staging7/7
and GLua306/0 pass. The fixture stager refuses occupied destinations and
records hashes before writing. Its synthetic cell is not evidence of actual
city-cell/loot eligibility. Restore its exact ledger-owned files and verify
launcher, marker and survivor persistence after the human review.
The isolated fixture ran on `zn_dev_prefab_anchor`/preview with one owner
and no loaded survivor. Synthetic cell0 spawned ten temporary props at five
compiled anchors, and the user confirmed placement/rotation and unscaled
stationary/movable collision. Owner-only return reached the preview launcher;
the marker was absent, stored city/preview persistence matched the baseline,
and the hash-verified temporary BSPs, prefab and ledger were removed. This
does not verify actual city eligibility, loot, multiplayer or scaled collision.
The same isolated fixture is currently staged again for scale review:
0.5x stationary and 2x movable barrels, five anchors/ten props, synthetic
cell0, one owner and no loaded survivor. Fixture-only scaling is guarded;
normal world scaling remains blocked. Offline spawn4/4, staging9 and
GLua308/0 plus live spawn4/4 pass. Ask the user to review visible scale and
walking collision, then return to the launcher, verify the baseline and
marker, and restore the exact hash-ledger files.
The user initially reported full-size collision on the small drum, then
observed that a box-shaped hull might explain it. Matched traces confirmed
client/server disagreement: typical 0.5x server7.03/client14.5 units,
2x server about28/client about14.5. The fixture is still loaded and owned.
Source now tries the documented tiny nonzero `SetModelScale` transition in
the fixture-only spawner; rerun the same comparison before drawing a conclusion.
Normal scaled spawning remains blocked. Return/ledger restoration still due.
The tiny nonzero-transition experiment failed: server collision for the
0.5x prop also remained about14 units. It is reverted to zero transition.
GMod issue #6405 suggests a client `Activate()` call; test only on the owned
fixture props and retain the documented client-physics caveats.
That fixture-only client activation brought all ten sampled client/server
traces within0.001 units, and the user confirmed walking/standing/pushing.
The isolated map now has an experimental automatic replication/transmission
sync; offline scale-sync1/1 and GLua313/0 pass. After a fresh fixture reload,
automatic activation matched client/server traces within0.002 units and the
user confirmed walking/pushing. Return to the preview launcher, baseline
comparison and hash-ledger cleanup all passed; temporary files are absent.
Normal-world scale remains blocked; actual PVS leave/re-entry, multiplayer,
additional models and deployed gameplay remain unverified.
The prefab library currently has only editor test documents, not an authored
roadblock or gate set piece. The existing gate cars/glass, approved motorway
art, lane/arrival behavior and `ZM_World` route authority remain unchanged.
Agree the first prefab content and replacement scope before integrating them;
the isolated fixture approval does not authorize a world refresh.
The user chose temporary mounted-prop roadblock/gate examples and an isolated
review, retaining existing gate cars. Source-only fixture9/9 and catalog3/3
pass; transition server12/12/client11/11 and GLua313/0 pass. Its left
north–south road has a three-drum roadblock and its right road an open-centre
two-drum gate placeholder, both using the approved straight-road reference.
It has no travel trigger and cannot prove gate functionality. Ask before
compiling/staging the new fixture; no production or full-world work is approved.
The user approved the single isolated compile. The room under
`generated/prefab_setpieces_20261029` passes VBSP/VVIS/VRAD, 4 clusters/
4 portals and 15 source/BSP checks; the known sky texture warning remains.
Hash-ledger staging supports both temporary prefab files and passes 11
fixtures. The user approved temporary staging and entry. The set-piece room
was loaded as `zn_dev_prefab_anchor`/preview with one owner and no survivor.
Status confirmed two anchors, the correct test prefab IDs and five props.
The user confirmed both road references and placeholder arrangements looked
correct. After return, the marker was absent, stored city/preview persistence
matched the baseline, and hash-ledger cleanup removed the temporary files.
This is isolated placeholder alignment, not final artwork or gate travel.
The user approved per-prop loot modes Off, Normal and Guaranteed, with
legacy/default Off. Normal retains the ordinary roll and spacing; Guaranteed bypasses both. For
Normal group overrides on models without a native rule, the author sets a
per-prop activation chance. Source now implements authoring, validation,
stable per-prop loot keys and atomic guaranteed-spot insertion without
resetting searched rows. Offline editor26/26, session12/12, spawn3/3,
owner8/8 and loot-validation1/1 pass; export28 and GLua308/0 pass. Fresh
live prefab19/19, loot23/23 and isolated spawn3/3 pass. A first live loop
failure was fixed; a later timeout was traced to a nested test include and
fixed with injected dependencies. The user confirmed the loot-mode,
group/chance and save/reopen controls using a disposable prefab. After return
to the preview launcher, the editor marker was absent and stored city/preview
persistence matched the baseline. Actual city-cell loot search/persistence
remains open.
Persisted loot acceptance now commits inventory and a conditional spot claim
in the existing inventory transaction, preventing duplicate grants after
write failure; stale offers, wrong profiles and failed declines report errors.
Transient runtime drops retain their separate behavior. Fresh live loot30/30,
inventory51/51 and isolated spawn3/3 pass; GLua308/0 and prefab runner14/14
pass. Actual deployed city-cell search remains unverified.
The user chose their existing preview survivor for a bounded city review.
`zn_test_prefab_city` is prepared: one transient prefab prop, a unique
throwaway loot profile and automatic decline; it does not grant inventory,
move the player or change cheats. It restores the active loot owner and
cleans up its test profile, with an explicit recovery marker on cleanup
failure. Offline safety2/2 and GLua315/0 pass; a launcher probe correctly
rejected the non-deployed context. Ask the user to deploy and confirm a
safe city cell, then verify actual map/cell/player state before running it.
The user deployed in preview logical cell14,0 on `zz_preview_ed3d3fa48090-cp`;
separate status confirmed world/loot cell302. The real-city probe passed1/1,
including candidate/target/search/decline and throwaway persistence, with no
position or inventory change during the probe. Active city loot was restored
and its marker absent. After user-approved return, the preview launcher kept
saved cell14,0 and stored city/preview persistence matched the baseline.
The anchor was synthetic; actual compiled-anchor eligibility, accepted
rewards, multiplayer and scaled collision remain unverified. A final source
change strengthens cleanup verification and passes offline safety2/2 but was
not reloaded in the city.
The user chose directional prefab spotlights with position, direction,
colour, brightness, cone angle and range controls; at most eight visible per
client, with only the nearest allowed to cast shadows. First prototype and
visually review one isolated editor light; preserve existing chest-lamp/CSM
owners and the shared engine shadow-projector limit. No spotlight content or
world rollout has yet been implemented.
An editor-only prototype now creates one shadowed warm spotlight and one
temporary stationary drum, with five-minute expiry and owner/map cleanup.
Offline client1/1, server2/2, atmosphere18/18 and GLua320/0 pass. It does
not save prefab light data. In a fresh editor the user saw neither light nor
shadow at brightness 1 in bright or simulated-dark preview; brightness 6
showed both, and the equally bright unshadowed comparison retained light
without the projected shadow. The user approved proceeding to configurable
prefab lights. Client/server probe cleanup was verified, and the launcher
return left the editor marker absent and survivor persistence unchanged.
This proves only the single-light prototype, not a default brightness or
the networked eight-light implementation.
The user chose the existing move/rotate gizmos plus numeric controls for
light authoring. A later live comparison found the manually drawn editable
client drum showed neither illumination nor a projected shadow while the
server drum showed both. Investigate editor preview rendering before
claiming a working light editor. The user also pulled global model search
forward: opt-in, incrementally indexed mounted-folder search now finds
multiword `oil drum`; the user found and added it in game. Offline editor28/28,
prefab runner20/20 and GLua320/0 pass. The rest of A3 remains deferred.
An isolated engine-drawn opaque client model was lit and cast a shadow.
After a temporary editor render-group change the user confirmed prop
appearance and move/rotate/scale; the initial light had no visible effect on
the moved prop, but after restart it was lit and its shadow followed movement.
A matched comparison then showed both engine-drawn and original manually
drawn client drums illuminated and shadowed when present before light update.
The experimental editor render-group change was removed; preserve the
original drawing path. Projector refresh timing remains an integration
concern and transparent models/lifecycle remain unverified. The comparison
resources were removed; the editor returned to the launcher with no marker
or loaded survivor, and stored survivor persistence matched the baseline.
The user requests a selectable list of available loot groups instead of the
current ID text box in the deferred A3 editor-UI phase. Preserve server-side
validation and the model-default option; do not redesign the UI in A2.
Spotlight source now includes validated saved/exported light data, editor
controls/gizmos/preview, server-owned transformed network entities and a
client pool (eight nearest, one shadow). Offline editor30/30, explorer7/7,
spawn5/5, runtime-owner9/9, pool5/5, preview1/1, world client1/1, prefab
runner23/23, export37, packaging68, CSM/chest5/5 and GLua331/0 pass. Current
world selection uses all networked lights without visibility filtering:
nearest-visible behavior remains unresolved. Live editor appearance, engine
replication, actual city, multiplayer and performance remain unverified.
GMod was launched on `zn_preview_start` with `-disableluarefresh`; after the
user confirmed readiness, status showed one human and no editor or survivor.
Fresh live prefab21/21 and spawn5/5 pass, including server light fields and
anchor transforms; a separate client report shows zero lights after cleanup.
The user then opened `test123`, saved a spotlight and reported no apparent
shadow on the bench. The editor is still open; preserve the saved file and
session. Client status reports one shadow-enabled projector and valid
texture, not proof of a rendered shadow. A temporary reference projector made
editable and server props cast ground shadows, but the editor projector did
not, even after matching settings and forcing an update. The temporary probe
is removed. Source adds actual-projector getter diagnostics (pool5/5,
preview1/1, world1/1, GLua331/0), not yet live-loaded. After an approved reload, actual projector getters matched the reference
settings and reported shadows enabled; no visible-shadow cause is proven.
The user saved their comparison work in `test123`; preserve the current file.
New owner-only probe controls remove the temporary
server drum and suspend/resume the editor projector. The user corrected their
earlier response: with the reference projector alone and no server drum,
editable props had no visible shadows. In a separate two-client-drum
comparison the user identified a shadow on the southern manually drawn drum.
In an empty-editor identity-matrix comparison, neither drum showed a shadow;
a subsequent engine/manual comparison was corrected by the user to say the
southern manual drum did have a shadow. The comparisons used different
positions, so the matrix is not proven responsible. Temporary resources were
removed and editor preview resumed. A new source-only owner probe toggles an
identity matrix on the same manual drum (client1/1, server2/2, GLua331/0).
The user saw that drum's shadow both with and without the identity matrix;
matrix alone is not the reproduced cause. An editable drum at the same
position showed no visible shadow under the same isolated reference light.
The probe is stopped; the editable drum remains unsaved. Source now supports
isolating the reference manual drum and applying the editor's skin/matrix/
bounds setup (preview1/1, client1/1, server2/2, GLua331/0). Ask before a
fresh reload or discarding that drum. Client world-light replication remains
unverified.
The user later approved the reload, then requested deferral of this shadow
issue to the end of Alpha 3.3. Temporary probe resources were removed and
client-confirmed absent; editor preview resumed. The user returned to
`zn_preview_start`/preview; separate status showed no editor or survivor,
the marker was absent and stored city/preview persistence matched the
pre-editor baseline.
The user chose prefab particles next: start with a selectable verified steam
effect, support continuous and individually triggered one-shot modes, include
steam sound, and impose no fixed simultaneous-effect cap. The mounted HL2
`train_steam.pcf` contains candidate name `steam_train`; the appearance and
lifecycle are unverified. First build one isolated editor prototype and obtain
visual/audio review before broader authoring or world integration.
The temporary steam/audio probe now has offline client3/3, server1/1,
editor30/30, packaging68 and GLua336/0; a fresh launcher correctly rejected
starting it outside the editor. Open an isolated editor and separately verify
client creation, then ask for visual/audio review. It does not save particles.
The first live candidate became invalid before the later status; the user
was unsure whether a puff or sound played. The original status path also
used a nonexistent getter while the effect was active. Source now uses
`GetEffectName` and tracks observed completion/invalidity; offline client4/4,
server1/1 and GLua336/0 pass. The probe was stopped and client cleanup
verified. Ask before reloading the current editor to measure actual duration.
After an approved reload, the user saw and heard the mounted steam example
and approved both as a starting point. The particle became invalid after
about 5.68 seconds without an observed finished state; it is not yet a
continuous effect. The prototype was stopped and its client resources
verified absent. Continue with a bounded continuous-loop prototype and
individually triggered one-shot design; do not claim world acceptance.
The source-only loop probe now recreates an invalid steam handle while
retaining its sound, with explicit replacement-failure cleanup. Offline
client5/5, server1/1 and GLua336/0 pass. It needs a fresh approved editor
reload and a multi-cycle visual/audio review; no continuous behavior is yet
accepted.
After an approved reload, the user confirmed the looping steam and sound
looked/sounded continuous and suitable; the probe was stopped and client
cleanup verified. Repeated one-shot triggers have a per-effect overlap
toggle, on by default; with overlap off, a new trigger restarts the burst.
These decisions authorize the particle authoring/world slice, not world
regeneration or acceptance of untested multiplayer behavior.
Particle data now has a packaged verified-effect catalog and optional
schema-1 records with stable IDs, transform, mode and overlap default true.
Storage/export reject unknown effects; world spawning explicitly rejects
particle-bearing prefabs until implemented. Offline contract9/9, storage10/10,
catalog2/2, editor session13/13, spawn6/6, runner26/26, export42, packaging69
and GLua338/0 pass. Continue with editor authoring and world triggering.
Editor particle source now includes catalog selection, handle/gizmo and
numeric transforms, Continuous/Triggered selection, overlap toggle and
explicit trigger preview. Shared lifecycle fixtures exercise 40 uncapped
overlapping bursts, restart-on-trigger and cleanup. Offline editor32/32,
session13/13, preview3/3, effect/probe6/6 and GLua341/0 pass. The source is
not yet live-loaded; fresh editor visual/audio/interaction review remains.
World particle spawning is still explicitly blocked.
The user confirmed editor continuous steam/sound and movement, triggered
preview/overlap, and save/reopen after a fresh load; live prefab23/23 passes.
Preserve their saved `teststeam` prefab. The editor remains open with one
owner and no survivor. World particle source now includes anchored continuous
emitters, individual Hammer inputs, uncapped triggered overlap/restart,
cleanup and an owner-only synthetic editor probe. Focused spawn6/6,
owner10/10, world client4/4, transport1/1, anchor input1/1, probe1/1,
anchor20 assertions and GLua351/0 pass. The source is not live-loaded;
ask before reloading the open editor, then exercise the synthetic probe.
Compiled Hammer routing (especially instance-local name fixups), multiplayer
and actual city behavior remain unverified. Keep the shadow issue deferred.
After an approved reload, the isolated synthetic world probe showed one
client continuous effect, two overlapping bursts and one restart-only burst
after paired triggers. The user confirmed continuous and triggered steam
were visible and audible. Probe stop and client cleanup were verified.
This is not compiled Hammer, city-cell or multiplayer evidence. The editor
is open; return to the launcher, verify the survivor baseline and run the
live launcher spawn suite.
The user returned to `zn_preview_start`/preview; editor marker absent,
survivor baseline matched, live prefab23/23 and spawn6/6 pass. A particle
variant of the hash-ledger stager and guarded compiled-anchor input command
are source-ready (stage14, owner11/11, retained BSP28, GLua351/0); inspection
is read-only and no staging ran. Ask before temporarily staging/entering the
exact fixture. It will not prove Hammer instance-name fixups or city play.
The user approved the fixture. Five compiled anchors produced five continuous
and ten triggered records; client status showed five continuous effects,
two overlapping bursts and one restart-only burst through the actual anchor
input. The user approved steam placement/audio. After return, client effects
were absent, marker and ledger-owned files were removed, and survivor
persistence matched baseline. Hammer target-name fixups, actual city,
multiplayer, late joins and matched performance remain unverified.
Preserve the sole-human editor guard and the user's approved A3 UI direction.

The [Alpha 3.2 tracker](docs/todo-alpha.3.2.md) is archived, not released or
fully accepted. Its remaining full-world outputs, Cell Health execution,
integration and carried Alpha 3.1.5 closure remain deferred, not prerequisites
to the prefab phase. Preserve accepted motorway/CSM checks and keep generator,
expensive output, production and publication work separately gated.

### Historical Alpha 3.2 chronology

The dated entries below preserve their checkpoint-specific status; their
"active", "next" and "pending" wording is historical. The Alpha 3.3 plan above
is authoritative for current priority.

- **Motorway source cleanup, 2026-10-28:** normal planning and emission consume
  approved trusted-plan motorway placements and gate records; the old
  mouth/connector survey, measured assembly-report workflow and complex
  inspection modes are retired. Normal roads remain on the 640-unit grid and
  `ZM_World` owns route availability. Focused source checks pass: motorway
  contracts132, retained corrected-plan/grid and gate writer/export checks1464
  and infill scope6; all96 saved motorway gate contracts match their entrances. No VMFs, BSPs,
  runtime exports or materials were regenerated, compiled or staged. The
  cleanup has not received fresh compiled/live verification. Continue to keep
  generator work paused and ask before any expensive output work.
- **Alpha3.2 revised focus, 2026-10-17:** the user reports all motorway gates work and alignment is perfect in game. The two corrected BSPs (`zz_preview_74c1b0c24754`, `zz_preview_a30b0e90c7e2`) are staged in `content/maps` and engine `garrysmod/maps`; hashes match the isolated builds. `content/data_static/zombiesim_world_preview.json` routes logical IDs454 and113 to those names via the targeted map-name updater; only those two `map` fields changed, and current plan/capture hashes were preserved for now. All336 active preview cell materials and map-browser thumbnails are refreshed and old `-edge2` cell images removed. A live load found missing skyline footprints for the two new map names; the targeted updater now emits matching footprint entries and temporarily reuses each replaced recipe's skyline model arrays. The updated manifest is staged and the same preview map was reloaded; user confirmation that the warning is gone remains pending. Keep the world generator paused and defer exact skyline models/full revision hashes to the later all-map export.
- **Phase J transition gate simplification, 2026-10-17:** gate access uses `CanTravelToNeighbour`/`ZM_World` exits as its only route-availability authority. The trigger-center comparison, invalid-measured-gate state, and runtime `route` default were removed. Optional `motorwayGates` records are used only for marker/arrival presentation. Server transition fixtures pass12/12 and GLua syntax passes277/0. Same-map reload and read-only gate report confirmed the west triggers published, the west neighbor available, and the marker unblocked; the user then confirmed all gates work.
- **Targeted runtime map-name update:** the preview world JSON now maps cells113/454 to the staged BSP names; the update changes only those `map` fields and preserves the existing revision hashes until the final all-map export. GMod was closed at the staging checkpoint; the later same-map runtime load and skyline-manifest follow-up are recorded above.
- **Preview cell material refresh, 2026-10-17:** rendered the current 336-recipe base plan and the two corrected-cell plans, then staged 334 unchanged base-plan images plus the two corrected images for logical IDs113/454. All336 runtime cell-material names match, every staged PNG decodes at1728x1728, and copied hashes were verified. Removed the336 stale `-edge2` cell images. Preview map-browser thumbnails now cover exactly the336 active runtime names; the original preview launcher thumbnail was restored hash-identically. The16 existing `map_layers` files had no `-edge2` names and were unchanged. Satellite/world-photo and navmesh-backed wireframe outputs remain for after CHM/navmeshes. No VMF/BSP/runtime-hash refresh or live reload occurred; temporary render folders were removed after staging.
- **Cell Health Manager batch controls, 2026-10-17:** the preview-admin grid reports navmesh presence, current-map clear/atmospheric PNGs and no revision hashes. The user approved an on-click "Start batch of unhealthy cells" control with unchecked-by-default navmesh/photo/cubemap options and a union target rule. The server recomputes the selected work and reuses the persistent composite `ZM_WorldCapture` queue; nav saves/reloads/validates before photos, never concurrently. Navmesh/cubemap work is per BSP, photos per logical cell. Cubemaps are manual only: prompt the user to run native `buildcubemaps`, ask after map reload whether it succeeded, persist Yes per preview map as `USER CONFIRMED`, and leave No incomplete while continuing. Partial photo imports merge only current-map captures and preserve matching existing images; use the existing watcher after restoration. Focused contract6/6, capture client7/7/server11/11, importer6/6, map/skyline updater9/9 and GLua syntax281/0 pass. The latest source was loaded with a same-map reload of `zz_preview_9a00023600b3`; the user reports the controls are visible/legible and the skyline warning is gone. The live client suite passes7/7; no batch has started, so actual maintenance execution remains unverified.
- **CSM current-check acceptance, 2026-10-17:** the user reports the current CSM implementation works and accepts its checks for now. Keep the default-off experiment and its documented technical limits; do not reopen its deferred lifecycle, multiplayer, or performance work without a new request.
- **Next-scope note:** the Cell Health Manager is a preview-only artifact grid
  and user-started maintenance control, not gameplay HP. Green means navmesh,
  both current-map photos, and a user-confirmed cubemap; the cubemap label is
  not engine verification. Keep all batch categories unchecked by default.
  Do not automate `buildcubemaps`, start a batch without an explicit button
  click, or start broad generator/revision work. First reload the current
  preview map with the latest source, then review the updated controls and
  confirm the skyline warning is gone. Any photo run still needs the existing
  watcher to merge/stage images; navmeshes use the existing staging command.
  Full-world output work remains separately gated and Phase K/L closure remains
  deferred.
- **Historical Alpha3.2 Phase J in-game motorway review fixes, 2026-10-15
  (incremental compile complete; live checks later accepted 2026-10-17):** complex motorway assemblies now
  shift in whole 320 steps so arms leave cells on the centre line, and
  continuation straights snap to whole 640 slots (`gridSnap` in the contract;
  (13,6) moves640 north). Residual authored mouth jogs (14-48) are Hammer
  fixes for the user. Land-side sky seal/black floor now end at2880/2944 (was
  3072/3136) so the skybox meets the outer ring. Shared recipes now emit a gate
  on every road connection (`gateDirections`); runtime still blocks per cell
  (49 recipes/98 cells previously lacked gates). Trees need natural, level
  ground across a192 canopy ring. **User rule:** verify alignment by sight in
  game; do not use motorway_geometry mathematical proofs as evidence.
- **Historical Alpha3.2 refresh status, 2026-10-16 (incremental compile complete; later live motorway checks accepted, full output/phase still open):**
  fresh seed-1337 preview plan has576 cells,336 city recipes,96 motorway
  assemblies and3 reusable safe-room maps. User-labelled Cell15,11 (plan grid
  14,23) now has a straight `roads/tile_road.vmf` center, east road ramp and
  bridge continuation. At this checkpoint, the two east `onramp-e` motorway
  cells shifted the ordinary road branch north640 while retaining the motorway
  piece; that per-cell shift is superseded by the lease-aware grid-slot rule
  above and must not be reused. The
  Army Base landmark cell's three fallback building slots now all use
  `tiletemplates/army`. Focused checks pass: bridge-ramp12, Army9, on-ramp20,
  complex gates234; GLua277/0. The complete-infill VMF emission completed
  (336 recipes; 335 refreshed, 1 retained). Required VMFs pass336/336.
  Visibility preflight covers339 maps:0 over portal/cluster budgets and0
  missing/invalid portal files. Incremental VVIS/VRAD covered all339 required
  maps:33 compiled,306 current/skipped,0 failed,0 incomplete. No skyline/runtime
  export, staging or live/visual review occurred; the compile is not phase
  acceptance. CSM now excludes `models/zombiesim/skybox/` before model
  measurement; GLua277/0 and focused offline CSM tests2/2 pass, but fresh
  in-game verification awaits deployment to a generated cell. The user raised
  the elapsed time; ask before further expensive skyline/material/staging work.
- **Alpha3.2 trusted motorway plan and lane gates, 2026-10-16 (source/test
  complete; no refreshed output):** the failed ramp face-ID refresh is not a
  prerequisite and must not be retried for this batch. The approved seed-1337
  plan and prior runtime gates are reused without current-source motorway
  geometry comparisons; dry validation preserves576 cell placements,336
  recipe names,96 motorway contracts and214 directional gate records. The
  migration removes only `-edge2`, retains `-oceanw`, and drops stale source
  fingerprints and the AABB-derived spawn candidate. Placement origins/yaws/
  leases/shifts remain identical. Runtime export hashes differ, with eight
  stale map names confined to ordinary cells without motorway gate metadata;
  topology and entrances still agree across all576 cells, and no old gate data
  is reused for those eight. New VMFs will use two lane-tagged triggers per
  motorway connection, preserving the256 arrow and384 arrival offsets;
  ordinary-road gates remain single. PowerShell parse, gate fixtures56/56,
  server13/13, client11/11, GLua277/0 and `git diff --check` pass. The migrated
  plan/list are written; the user authorized the full preview refresh, compile
  and map-only staging. Navmesh/Satellite/material capture, production and
  live visual acceptance remain excluded; visual alignment still requires the
  user's in-game review.
- **Generated-output retention, 2026-10-15 (user directive):** do not keep old
  generated maps, BSPs, VMF batches, skyline models or map materials to compare
  earlier phases; the current generator output supersedes them. Delete
  superseded batch/test folders once a newer batch is staged, and do not keep
  duplicate BSP/content copies of a staged batch. The Phase J preview (339 maps)
  is the installed baseline; the old Phase B staging ledger and its backups
  were deleted (record: `generated/phase_j_preview_20261015/retired-staging-ledger.json`),
  so there is no restore path to earlier preview worlds. Keep tool caches
  (`clothing_preview`, `sky_catalogue`, `launcher_*`) and source backups.
  Custom test worlds (for example oceanw/edge variants or isolated fixtures)
  are fine during a phase, but delete their maps, materials, skyline models and
  generated folders once that phase's checks finish. Drive space is limited;
  this cleanup once recovered ~33 GB.
- **Alpha3.2 normal wide-motorway cells approved, 2026-10-15:** all27
  complex/mixed preview cells now come from the normal planner (schema-2
  `motorwayAssembly`, measured assembly report required at that checkpoint). Approved fixtures are
  instance-identical; user approved new cells0,7/12,7/23,18/15,18 in Hammer++.
  Roads stay on the5x5 grid, joins use corner/straight/corner doglegs, no bend
  connectors, T skipped. Motorway geometry fixes are user-owned in Hammer.
  This checkpoint's measured-report normal path is superseded for the current
  trusted Phase J refresh above; reports remain diagnostic-only there.
  Quick review tool: `build_motorway_cell_preview.ps1 -NormalComplex -SkipInfill`.
  Periodically delete superseded `generated/` test folders (keep ledgers/backups).
- **Alpha3.2 measured complex travel preparation:** user explicitly approved
  refreshed crossroads and synthetic motorway T whole-cell geometry; do not
  reopen those Hammer reviews. Complex contracts now retain their source
  coordinate frame. Source-backed gate candidates check saved flat floor
  windings across the trigger, arrow and arrival; stale source hashes,
  unsupported decks and physical gaps reject explicitly. Normal export/emission
  is still straight-only: these candidates do not enable diagnostic cells.
  The centred south corner approach uses the existing ordinary-road96/128
  arrow/arrival insets (live travel review pending). Its candidate gate is0,-2720 at deck36, arrow0,-2624,
  arrival0,-2592; reviewed geometry is unchanged. Runtime now accepts explicit
  one-lane `road` contracts separately from two-lane motorway contracts, rejects
  shared-map route/count conflicts and preserves legacy markers/barricades.
  Fresh server markers12/12, client10/10, GLua275/0 and motorway1529 pass.
  Seven whole-cell3436 remains passing. Live ordinary-road travel, normal
  complex planning/reservations/export and staging remain pending.
  Full density plan still contains69 plain straights plus27 complex/mixed
  motorway cells. Standalone single/dual on-ramp ordinary mouths remain offset
  (512/256 units in current canonical fixtures); the approved mixed1408-unit
  dogleg is not automatically valid there. Their mouths are also off the640
  road grid (1920 from centre, leaving960 to the edge), so native corners and
  straights cannot centre them. User rejected generated bend/S-bend connectors
  (2026-10-15): never create bend connector pieces; join roads only with native
  corner/straight pieces and do not move normal road positions. The rejected
  bend code and sources were removed. User chose to leave standalone on-ramps
  as they are for now and continue the rest of Alpha3.2.
- **Alpha3.2 junction coverage refreshed:** matching full density plan has4
  motorway crossroads,0motorway T and172ordinary road T cells. Motorway T
  remains an explicit synthetic whole-cell fixture. Fresh seven-cell3436
  assertions/7required VMFs pass under
  `generated/phase_e_junction_cell_verification_20261014`; exact crossroads
  and motorway T both pass VBSP/portals/VVIS/VRAD (preview fast/pool1).
  The user explicitly approved both refreshed junction arrangements.
  Other five fixtures were structurally checked, not recompiled. Diagnostic
  fixtures are not normal gate/runtime integration or live acceptance.
  User also approved final corner cleanup and confirmed missing corner infills
  are expected. All four mixed layout reviews are satisfied; do not reopen.
- **Alpha3.2 mixed correction review:** four current-source fixtures under
  `generated/phase_e_mixed_centred_routes_20261014` pass VBSP/portals/VVIS/VRAD
  (preview fast preset); four new Hammer++ windows are open, old work preserved.
  Bridge dominates cell centre; south/north terminals are0,+1280 / +16,-1280.
  Mixed ramp wide owners remain unchanged. Both ordinary-road entries snake
  from the true central side axis through corner/768-unit straight/corner;
  user explicitly approved the extra128 rather than moving wide pieces.
  Source initializer preserves editable connector changes; actual floor edges
  validate all joins. Mixed automatically uses complete rectangular infill,
  preserving accepted corner exclusions/sub4 limits. Fresh motorway1529,
  density2633, mixed infill27022/128 rectangles pass. User approved both bridge/
  deadend layouts, deadend/on-ramp and the corner connecting row. The remaining
  corner correction replaces only obsolete S-border road slot2,5 with planned
  terrain. Fresh `generated/phase_e_corner_terrain_cleanup_20261014` passes
  the same fast compile/portal/infill checks; all three approved control VMFs
  are byte-identical. Do not reopen their human layout approval.
  `ordinaryRoadApproaches.boundaryPort` is the centred road contract for later
  gates; the south row lies at-2560, so do not blindly reuse old2208 gate axis
  over empty floor. Normal mixed gate/runtime integration remains pending.
  Normal straight emission/2-map compiles/4 gates+arrivals now pass; fresh
  crossroads VBSP passes. Two-cell runtime export correctly rejects incomplete
  24x24 data. No staged/live/player/profile changes; no Phase E acceptance.
  This supersedes earlier guarded/no-compile/source-policy-pending notes below.
- **Alpha3.2 measured straight gate writer, 2026-10-14:** normal straight VMF
  gate selection remeasures source and compares planned records/active entrances.
  Trigger extents1456x64 at Z32..144, measured lane arrival Z72 and existing
  car/glass composition translated to carriageway centres are wired in source.
  Legacy trigger256x64/props unchanged; inspection emits no gates. Fresh
  motorway1405/density2633 pass. Normal-wide emission guard remains until
  runtime markers/arrivals integrate; no VMFs/BSPs/staging/live changes.
  Compiled barricade/trigger collision and appearance remain later batch gates.
- **Alpha3.2 measured straight gate contract, 2026-10-14:** normal straight
  plans derive lane/deck/arrow/arrival metadata from current saved floor faces.
  Canonical lanes416 wide at Z68, centres-512/+528, transformed to N/W
  -512/+528 and S/E -528/+512 outward-right offsets. Gate2208/mouth2240,
  arrow256 inward/arrival384 inward unchanged. Straight-only stale registry
  IDs252/258 corrected to actual342/384; no authored asset edits or bridge
  registry changes. Fresh motorway1352/density2633 and actual two-plan/four-
  direction records pass. Normal brush/prop/marker/runtime consumers remain
  pending and emission guard remains. No compile/staging/live changes; CSM
  deferred and rectangular-building live validation awaits authored asset.
- **Alpha3.2 resumed density/motorway priority, 2026-10-14:** user approved the
  reconciliation and resumed work. No ordinary rectangular building exists;
  its physical/live validation waits for the user's eventual asset, not this
  release's generator work. CSM remains deferred. Normal plain-straight core
  planning now shares the accepted stripe geometry and reserves15 slots before
  density decorations (five owners/ten suppressed). Two fresh normal-planner
  recipes prove both orientations without inspection metadata; their legacy
  fixture manifest is not new density-output evidence. Fresh motorway1082,
  density2633, rectangle555 and entrances12+2 pass. Suppressed dimensions remain
  consistent with owners through planner defaults and builder validation.
  Normal VMF emission remains deliberately
  blocked until rings/gates/runtime integration; no compile/staging/live changes.
  Phase E remains active, not accepted. Existing bounded preview approval stands.
- **Alpha3.2 reconciled status, 2026-10-14 - authoritative over older next-action
  notes below:** user paused execution for a complete audit. Read the current
  reconciled-status section at the top of `docs/todo-alpha.3.2.md`. Phases0/A/B/D
  accepted; both straight and all seven complex motorway cells were reviewed.
  Accepted isolated inspection fixtures are NOT normal-world rollout: retained
  full density-preview plan has96 motorway cells, no measured assembly metadata
  and1x1 road placement records despite wide-source remapping. Its336/338
  compile has only two crossroads failures; fixing them alone does not complete
  widened reservations/rings/gates/runtime/derivatives. E helper work is isolated
  source preparation; no ordinary rectangular buildings installed. Do not
  reopen accepted artwork/yaws or turn historical join residuals into new
  connector-authoring requirements; retained Phase B limits are not erased.
  Minimal brush41926 repair and the bounded preview generation/compile/
  derivative/backed-up staging/launch batch are now approved. Brush edit has
  verified backup but no new compiler verification; do not call it fixed yet.
  F/G/I integration/review and final J/K/L remain open. Full navmesh/Satellite
  closure, production/publication remain separately gated. CSM experiment
  accepted with further work deferred; M cancelled/removed; fixed landmarks
  density-exempt, never relocated. Audit changed documentation/status only;
  no generation/compiler/staging/live transition/player changes ran.
- **Alpha 3.2 motorway origin emission, 2026-10-14:** core/ring VMF emission
  now consumes measured owners' explicit `originCellLocal` XYZ instead of
  recalculating the rectangle centre. Shared production writer preserves
  fractional coordinates/invariant output and rejects missing/non-finite
  origins, occupied-slot emission and incompatible frame/pitch/tile-Z shifts.
  XYZ is already physical cell-local: do not rotate it again or add tile Z.
  Isolated motorway mode remains required; ordinary centred origins/interior
  rounding unchanged. Fresh motorway1074, rectangle555, entrance12+2 pass;
  all18 retained straight core/border/outer VMF transforms match the writer.
  This is entity-output/retained-artifact compatibility, not a fresh complete
  map, compiled or live acceptance. No outputs/assets/settings/live state
  changed. Phase E remains open for normal planner and complex assembly
  origin/ring/gate/travel integration. CSM deferred, M cancelled; broad output
  batches and crossroads brush repair remain separately gated.
- **Alpha 3.2 motorway focus and straight contract, 2026-10-14:** user confirmed
  the scope clarification and asked to continue. Prioritize motorway origins/
  rings/travel; retain ordinary rectangle helpers without expanding building
  features next. Builder uses shared read-only straight corridor validation:
  nine distinct owners,27 exact leases,25 unique core slots, approved finite
  origins and matching rotated footprints; suppressed slots cannot emit or
  reference another owner. Inland-straight limits still reject water/ocean/
  den cells. Fresh motorway710, rectangle555 and ordinary entrance12+2 pass;
  both retained straight plans pass27 leases each. No output generation,
  compiler/staging/live reload or authored edits ran. This does not enable
  normal wide-motorway planning or accept Phase E. Complex joins, full
  origin/ring/gate/travel integration and physical/live evidence remain open.
  CSM deferred, M cancelled; broad batches and crossroads source repair remain
  separately gated.
- **Alpha 3.2 Phase E filename/inventory source slice, 2026-10-14:** shared
  `_WxH`/legacy `_Wx` parser wired into marker inventory, height selection,
  compact macro names and zoo/test helpers. Ordinary limit stays3 per axis;
  forced oversized rectangles fail explicitly. N/S midpoint uses authored
  height, E/W width; zoo spacing uses both axes and multi-tile tests distinguish
  authored markers from rotated occupancy/origins. Fresh rectangle555,
  density2529 and ordinary entrance12+2 pass. No new ordinary rectangle building
  exists in inspected inventory; no authored assets/settings changed. Full
  frontage/multi-tile output tests, end-to-end small-output and compiled/live
  verification remain open; first E checkbox is not complete/accepted.
  No world generation/compiler/staging/live reload ran. M cancelled, CSM
  deferred, expensive batch and motorway source repair still separately gated.
- **Alpha 3.2 Phase E rotated frontage source slice, 2026-10-14:** marked
  candidates validate rotated reservations but transform markers from authored
  dimensions; generic frontage uses authored direction and the same axis swap.
  Building/forced/landmark reservations, caps and commercial access use those
  dimensions. Commercial cache keys distinguish rectangles at one anchor.
  Fresh rectangle/frontage475, density/recipe2529 and ordinary entrance12+2
  pass;24 paired square marked/generic scenarios exactly match committed
  candidate order/targets. An initial square tie-order discrepancy was fixed.
  No assets selected or maps generated/compiled/staged/live-reloaded.
  Rectangle filename parsing and authored direction-marker inventory validation
  remain square-only and are the next boundary; first Phase E checkbox remains
  open. Full frontage/multi-tile output tests and physical/live acceptance remain
  unrun, not implied by helper fixtures. M stays cancelled; CSM stays deferred.
- **Alpha 3.2 Phase E explicit occupancy source slice, 2026-10-14:** the
  planner/builder accept explicit rectangles1..3 per axis with one emitting
  owner. Planner rejects empty/reused IDs atomically; builder rejects duplicate
  emitting IDs and inconsistent template/yaw/explicit occupied dimensions.
  Legacy records without repeated dimensions retain owner geometry.
  Fresh rectangle342, density/frontage/recipe2528 and ordinary entrance12+2
  fixtures pass; current validator passes576 retained ordinary cells and two
  retained straight motorway inspection cells. No maps were generated/compiled/
  staged or live-reloaded. This is source/compatibility evidence, not Phase E
  acceptance. Ordinary rectangle filename selection, rotation-aware frontage,
  authored offsets and ring/travel integration remain open; do not wire new
  user tiles or widen size limits without inspecting their actual contract.
  Phase M stays cancelled and CSM stays deferred.
- **Alpha 3.2 Phase M cancelled / Phase E next, 2026-10-14:** the user
  rejected the safe-zone detail effect and the underlying idea. Do not resume
  M0-M6, request more detail reviews, or design another neighbor-claim system.
  Removed optional detail settings handling, two-pass scenery reservations,
  claims/diagnostics, recipe/variant signature contributions, builder emission
  and dedicated detail tests. Existing safe-zone entrances, identities, density,
  roads/coast and unrelated generator work are retained. Preserve the user's
  authored VMF/VMX files; old isolated detail fixtures are rejected history and
  must not be staged. No detail-bearing world was staged or player data changed.
  The user's replacement direction is larger, interesting authored tiles with
  varied widths/heights placed through the ordinary generator. Follow Phase E
  footprint/instance/ring/gate integration; inspect actual assets before wiring.
  Earlier M0 design approval and M1/M2 progress below are historical and
  superseded, not pending acceptance work. CSM remains deferred, the two prior
  motorway VBSP failures still need author repair permission, and expensive
  builds/staging/production/publication remain separately gated.
  Removal validation: affected PowerShell parses/editor diagnostics pass;
  current density/selection/recipe-identity fixtures2528/2528 and fresh ordinary
  entrance fixtures12orientation/water +2rejection pass. `-FixturesOnly`
  skips the full-preview entrance baseline without changing default behavior.
  Ordinary variety/route checks4807/4807 pass on the retained576-cell/335-recipe
  plan; this is not a new generated-world or live acceptance. No Lua or authored
  VMF/VMX changed in removal, and no build/staging/live reload ran.
- **Alpha 3.2 experimental CSM accepted / remaining CSM deferred:** the user
  explicitly accepts the current default-off, client-local additive experiment
  and its Options enable/Low/Medium/High controls. The weighted nested1/2/3
  projectors at15/30/rendered-frame `Update` rates are not seamless conventional
  cascades or a proven GPU refresh optimization. GLua275/0 and diagnostics pass;
  the new runtime/Options source has not been live-loaded, and full lifecycle,
  skybox/capture, multiplayer and matched foreground performance remain
  unverified. This is limited-scope acceptance, not fabricated test evidence.
  All remaining CSM work is saved in [docs/csm-implementation.md](docs/csm-implementation.md)
  outside Alpha 3.2's completion gates. Do not resume CSM probes, optimization,
  reloads or benchmarks unless explicitly requested. Keep default off and baked/
  shared lighting unchanged. The F-toggle chest lamp remains unshadowed while
  CSM is off; when CSM is ready, only the local player's lamp casts dynamic
  shadows. Sun-shadow coverage follows the local player's entity origin rather
  than the render camera. Runtime trees cast while CSM is active; bushes/hedges
  and high-poly non-foliage models are suppressed, with original flags restored
  on CSM off. Compiled static props remain unchanged, so hedge cost and
  moving-shadow popping remain unresolved.
  Resume E/F/G/I/J/K/L; the rejected M system is no longer a prerequisite.
  The336/338 isolated preview batch is not stageable:
  the two motorway-crossroads VBSP failures require author permission before
  geometry repair. Expensive output/staging, production and publication gates
  remain unchanged.
- **Historical pre-rejection Alpha 3.2 Phase D/M0/M1 evidence, 2026-10-14:**
  M0/M1 approval and detail work below are superseded by Phase M cancellation
  above; the density and unrelated compiler/CSM evidence remain scoped history.
  The user
  accepted density selection, fixed-landmark exemptions, complete occupied
  route adjacency, the four-variant cap and current recipe growth. The isolated
  seed-1337 preview produced a 576-cell/335-recipe plan (+24, 7.7% over the
  311-recipe baseline), 335 layouts and no missing required VMFs. Plan-level
  variety passes 4,807 assertions; actual layout adjacency passes 5,966;
  required cells are 335/335. The user accepted deterministic entrance slot
  changes at (16,0), (22,12) and (3,18). No compilation, staging, live or visual
  review occurred; the temporary generated probe was removed. Phase M0 design
  decisions and the two test blockouts were reviewed and accepted. M1 claim
  planning is now authorized. Use one-tile-deep neighboring outer-ring claims;
  approved NW, cardinal-edge and Epicenter mappings; Lab/Epicenter are
  landmark-driven, with Lab claims anchored to its actual 2x2 footprint;
  detail faces point toward the source, using a horizontal tie-break for
  diagonal claims; missing family assets are diagnosed and skipped;
  active dens use Hospital/Army Base/Bunker identity or default; details are
  untagged, W/E-canonical, visual-only and lose to higher-priority claims.
  Storm Drain gets N/S flanks and westward pipes ending at the existing coast;
  piers, harbors and naval silhouettes are out of scope. Two clearly marked
  source test blockouts (Default-den and Hospital) exist under
  `tiletemplates/safezone_detail`; normal settings do not select them. The user
  revised the Default-den blockout for a more generic fit and approved removal
  of an exact duplicate brush from both its VMF and VMX. Current tile structure
  passes balanced-brace, unique-ID/bounds, six-sided-solid, CRLF and route-marker
  checks; the mounted material resolves from `garrysmod_dir.vpk`. The ground-grid
  suite passes 56 assertions. The refreshed two-tile zoo is open responsively in
  Hammer++, but the revised appearance has not received a new human acceptance.
  M1 planning now resolves claims against a high-priority-only pass, then
  reserves accepted incoming tiles before ordinary single-tile, macro and open
  scenery selection, including variant rebuilds. Focused claim tests pass 43
  assertions; entrance integration plus claim-aware variation passes 963
  assertions across 16 cells/11 recipes/22 adjacent pairs and confirms two
  ordinary scenery slots are reserved. The user explained that the multi-tile
  fixture's old `tile_building_1b_2x.vmf` reference was obsolete after renames;
  it now points to current `tile_building_2aa_2x.vmf`.
  The user authorized a full isolated seed-1337 preview regeneration/compile.
  Current generated data has576 cells/335 recipes, tier counts72/120/384,
  density policy v1, plan adjacency4807/4807 and actual layout adjacency
  5966/5966; required sources are335/335. The isolated 338-map fast compile
  finished 336/338. The two VBSP failures,
  `zz_preview_97dcc3127e09` and `zz_preview_99a2fd788b1e`, both instance
  `tile_motorway_crossroads_6x3.vmf` and fail on brush41926 (`bounds out of
  range` / `HashVec: point outside valid range`); no VVIS/VRAD ran for those
  two. They are not staged; do not edit the user's motorway source without
  approval. CSM feasibility was explicitly pulled forward to run alongside this
  batch. A manually invoked local-only ProjectedTexture probe and preview-admin
  status bridge are in `gamemode/tests/cl_csm_feasibility_probe.lua` and
  `gamemode/sv_dev_console.lua`; GLua274/0 passes. `util.GetSunInfo` returned
  no enabled sun, so a test-only direction is derived from the preview base
  `light_environment` with an explicit Source-branch caveat. The user visually
  confirmed the orthographic sunlight probe casts world/telephone-pole and
  tree-leaf shadows in the reviewed cell. Its final CPU `Update` timing is
  0.134ms average/1.003ms max over1718 calls, not full render cost.
  A gameplay light-only chest lamp is implemented at the F/native-flashlight
  bind: server NWBool state, local player center, replicated cones on every
  client, nearest-four/2048-unit render cull, all chest cones unshadowed, and
  death cleanup. F on/off passed on the preview survivor. A/B/A shadowed
  chest-light profiling measured22.5/59.8/26.6 FPS; the permanent unshadowed,
  transform-cached lamp measured59.5 FPS versus59.8 off, with captured0.262ms hook
  average and0.675KiB/frame allocation (correcting the earlier0.081ms summary).
  The user later noted the game may have
  been unfocused during capture; focus was not recorded, so these FPS pairs are
  not matched causal evidence.   No baked/shared lighting changes occurred. `SetSkipShadowUpdates` was
  available but visually lost/staled the reviewed shadows and remains off.
  A test-only rate limiter exposes 15/30/60Hz probe updates. Bridge-started FPS
  profiles reported44.37FPS with one projector at60Hz,59.80FPS after removal,
  and22.85/23.31FPS at15Hz, but a foreground-window monitor during the latter
  run recorded GMod in0 of159 samples. The bridge workflow left VS Code active;
  none of those profiles establishes foreground CSM cost or a rate benefit.
  The temporary probe was stopped and verified projector-invalid.
  `gamemode/cl_csm.lua` now owns a client-local, default-off CSM prototype and
  Options toggle/quality selector. Low/Medium/High use1/2/3 weighted nested
  projectors at15/30/full rendered-frame updates. The layers currently overlap
  without seam masks; cascade appearance, dynamic-caster accuracy, lifecycle,
  skybox behavior and performance remain unverified. It uses
  `render.GetViewSetup(true)`, suspends for known launcher/inspection/capture
  contexts, and removes all owned projectors when disabled. GLua275/0 and
  Problems diagnostics pass, but the running client has not been reloaded with
  this source; no runtime/Options live or visual test is claimed. The user
  subsequently accepted the experimental scope with these limits, as recorded
  above; further CSM work and a manual foreground profile are deferred. No staging or full
  capture has run.
  Do not alter the preserved entrance/detail walls. Other authored assets,
  compiles, skybox model builds, staging and visual acceptance remain gated.
- **Alpha 3.2 Phase B acceptance record, 2026-10-15:** the user
  accepted Phase B with exact floor-mouth seams still clearance-pending and
  incompatible motorway/road connections explicitly unsupported. All emitted
  assembly examples stay inspection-only. The seven final bounds-based
  complete-cell fixtures passed VBSP/VVIS/VRAD 7/7, within portal budgets
  (maximum 370/1,064), and the user reviewed them in Hammer++ and accepted the
  phase with those limits. The user then approved U4/U8 infill for any
  bounds-verified rectangular gap. Fresh U4/U8 regression passes 78,498
  assertions; complete-cell integration passes 3,579, with 390 integer
  rectangular instances across seven cells. The observed T-junction 13x256
  gap now emits U8 + U4 and leaves only its 1-unit remainder on the black floor.
  Updated outputs are isolated under
  `generated/phase_b_u4_u8_infill_20261015_176149103747430597768558764c2f0d`;
  VBSP/VVIS/VRAD pass 7/7, with no failures or incomplete stages. Portal
  budgets pass 7/7 (maximum 365 clusters/1,055 portals against 1,500/2,700).
  The user reviewed and accepted the four refreshed U4/U8 cells (crossroads,
  synthetic T-junction, deadend and single ramp) after they were opened at
  their exact paths in Hammer++. This follow-up does not re-open accepted
  connector policy or authorize staging/production.
- **Alpha 3.2 Phase D source inventory, 2026-10-15:** active settings now map all
  five motorway topologies and three motorway transports to the approved
  `roads/motorway_3x1` files. Retained `motorway_1x1` sources are mapped
  explicitly inside the isolated inspection wrapper only; the active wide
  motorway variant pool is empty because the approved inventory has no
  footprint-compatible alternatives. Removed missing untagged border paths
  and selected the compatible `tile_border_wall_corner_1a.vmf`. Planner
  preflight validates 67 explicit tile paths and requires all motorway
  topology/transport keys; motorway straight, center and dead-end selection
  cannot fall back to terrain. Inventory tests pass14/14, motorway inspection
  568/568, source geometry614/614 and ground-grid56/56. Re-audit of the newer
  user-edited T-junction source found one repairable 0.388-unit offset in a
  single640x640 ground slab; the approved ground-only repair made a hash-backed
  source backup and leaves zero reported ground-grid issues. The separate
  `test_outer_edges.ps1` still fails before planner invocation because its
  fixed-prop count expects2 dynamic props in `tile_edge_ra_wall_1aa.vmf`, while
  the unchanged source contains4; this is not caused by this slice and remains
  open. No full-world plan, map compile, staging or publication ran. Phase B's
  accepted connector limits remain unchanged.
- **Alpha 3.2 rectangular infill correction, 2026-10-14 (initial 16-unit minimum; superseded below):** user rejected
  the polygon/decimal infill approach. Only recognized standard ground bases
  generate infill. Independently, inspect each authored brush's bounds within
  the Z0..32 fill slab and exclude intersecting candidate regions; this does
  not turn arbitrary brushes into ground sources. Use full
  640x640ground first, retain320x640half/320x320quarter, and use strict powers
  of two16..512for both dimensions of extra patches. Nothing below16is emitted;
  fractional/sub16remainders stay on the black floor and are explicit metadata.
  Do not recreate `tile_ground_shape_*` or decimal `p` source names.
  Proven ground-only repairs:39brushes/28sources with verified originals and
  all other fields unchanged; subsequent audit finds zero recognized defects.
  Explicitly removed61shape/12decimal source files with hash-backed backups,
  then archived76unused unmodified rectangular defaults. Current power2
  fixtures use30source templates (previously75), now472instances and36omitted
  sub16remainders. Strict sizing increases instance count versus arbitrary
  polygons; do not claim an instance-count reduction. Fresh infill87599,
  complex3613/ground56checks pass; PowerShell7/7 and protected inputs pass.
  The first decorative correction explicitly protected the concrete and
  dirt-lip surfaces in `tile_bushes_1aa.vmf`; that source-specific exception
  is now superseded by a material-independent geometry-bounds check described
  below. Older fixtures referencing retired sources are stale.
  Preserve approved roads.
  On 2026-10-14, the user requested Phase B completion. Fresh current-source
  geometry614, survey5696, assembly1806 and complete-cell3625 assertions pass.
  The seven refreshed complex cells completed VBSP/VVIS/VRAD7/7 under the fast
  preset; all are within the 1500-cluster/2700-portal budgets (maximum
  365/1055). This bounded compile does not prove collision/travel or resolve
  the exact/diagnostic lane joins and road approaches. Updated-infill human
  review remains pending after Hammer++ did not retain all seven launched
  fixtures. A later crossroads inspection traced duplicate fills to the
  authored concrete solid1945 and adjacent dirt lip solid1946 in
  `tile_bushes_1aa.vmf`. The exact-source signature check was only a narrow
  interim fix; it is replaced by the regional bounds rule in the active
  tracker. No materials or solid IDs are used to decide whether an authored
  brush occupies candidate ground.
  The user then confirmed checking all open Hammer cell previews and that they
  looked fine, and closed the editors. The latest isolated bounds outputs were
  generated afterward and were not opened by this run. Fresh infill68868and
  complex3357 assertions pass; seven final layout fingerprints match their
  VMFs, with344 emitted rectangles versus472 in the prior seven-cell output.
  No new compile, staging or production build ran. At that checkpoint Phase B
  remained active; no staging/production authorization was implied.
  Continued connector measurement: ordinary road side54 is256wide/Z36;
  ordinary bridge side276 is256wide/Z196, compared with the approved wide
  bridge Z196.057. This0.057deck difference is measured, not permission to
  move either source. Current ordinary ramp branch end floors remain Z68/96.
  On 2026-10-15, the user chose to defer connector assets and keep incompatible
  motorway combinations and ordinary-road approaches unsupported. The survey
  now labels48 exact surface seams as clearance-pending candidates,24
  mismatched motorway mouths and20 road approaches as unsupported; every
  generated assembly instance is `inspection_only`. Fresh disposition checks
  pass1900 survey and3487 complete-infill assertions. The final bounds-based
  complete-infill fixtures then passed VBSP/VVIS/VRAD7/7 and portal budgets,
  maximum370 clusters/1064 portals. That compile does not establish collision
  clearance or live traversal. At this checkpoint acceptance was still
  pending; the user subsequently accepted Phase B after reviewing the final
  compile fixtures, as recorded above.

- **Alpha 3.2 nine-cell visual review accepted, 2026-10-13:**
  user checked all nine complete motorway cells, adjusted their source tiles
  and explicitly approved the results as perfect. Preserve that artist revision;
  do not reopen the same visual checks or revert the geometry. Current measured
  bridge road deck is196.057; single ramp road mouth is Z80/grade-112/192,
  dual ramp mouths remain Z96/grade-0.5. Dual upper lane face ids now
  W3470/3518 and E3308/3314. Ordinary approach mouths are Z36 and Z68/96.
  Fresh survey5696/assembly1806 assertions pass:48exact/24diagnostic seams
  and20pending approaches across32rotations. These counts do not prove compiled
  collision or fix the remaining ordinary-road grade/deck and combined topology
  contracts. Phase B remains active; costly builds remain separately gated.
  The earlier park whole-source centering moved its already-canonical direction
  marker off the south midpoint; restored only that metadata marker to0,-640,32.
  Current-source complete refresh at `generated/phase_b_approved_cells` passes
  infill271950/complex3311/ground56/geometry614 assertions,321ground instances.
  Protected settings/tuned plan/both runtime JSON hashes remain unchanged.
  Cleanup audit finds75active sources and36unused byte-identical defaults;
  these36remain pending archive to preserve references in reviewed/open old VMFs.
  No compiler, world rollout, staging or live test ran.
  User chose separate connector/approach authoring requirements, not deferral
  into Phase D. The active tracker now records nine measured requirements,
  exact exceptional edge contours, source-local coordinates and bounded
  authoring/integration gates. Phase B stays active; next is measuring the
  ordinary-road/bridge far endpoints and span/clearance for a proposed isolated
  connector, then approval/authoring. Do not invent lengths, tolerances or alter
  approved motorway art to make the existing provisional approaches fit.

- **Alpha 3.2 complete infill / cleanup / building audit, 2026-10-13:**
  complete projected ground now uses320editable instances across seven complex
  cells. Infill271563assertions cover actual convex overlaps/planes/half-spaces
  and six complete non-corner ground frames at four cardinal rotations; the
  approved corner is retained, not declared newly complete. Stable round-trip
  polygon/dimension identities prevent duplicate defaults. Fixed a shared-array
  winding bug;34verified legacy defaults repaired with originals archived.
  Explicit cleanup archived92unused unmodified defaults;76sources remain.
  Artist/VMX ownership, active dependencies and half/quarter bases are protected;
  tagged64x320and320x192sources remain used. Superseded fixtures may need archived
  sources restored before use. Complex complete-mode3309/determinism passes;
  no BSP/live acceptance inferred. Nine complete-cell VMFs (two straight plus
  seven complex) are open in Hammer with exact native captions verified9/9;
  all nine editors respond. Subsequent human review is accepted as recorded above.
  User additionally authorized building alignment repair. Audited41building
  sources: eight had plain ground-plane-only errors (not shifted buildings);
  2x park's31partitions prove a full1280-square footprint at Y+32, corrected
  by moving its entire source Y-32. Army-wall X2.542 corrected as a whole
  source. Displaced/partial references remain explicitly limited; do not snap
  their geometry. Ground fixtures55pass; source originals are hash-backed.
  Keep working in Phase B; no costly/world/production/staging work authorized.

- **Alpha 3.2 ground contract / origin repair, 2026-10-13:** user requested
  shared ground-only classification and alignment warnings across tile use.
  Use existing640x640/Z0..32 world-box bases with known top/side materials;
  never classify other geometry from material alone. Center tiles using a
  complete declared ground footprint, not decorative bounds or asymmetric
  surviving ground. Move the entire source only for a confirmed common offset,
  preserving roads/props and UVs; otherwise snap proven ground-only errors.
  `tile_ground_grid.psm1` owns shared classification/warnings. Explicit
  `repair_tile_ground_grid.ps1` defaults to audit-only and keeps verified
  originals; generation never edits sources. T-junction Y-0.388 corrected
  as a whole source, plus31ground brushes across T/dual/ordinary ramp.
  T north continuation X306.00005 remains lane-derived; do not round it.
  The separate army-wall X2.542 offset was initially retained as a warning;
  its subsequent user-authorized whole-source correction is recorded above.
  Isolated `generated/phase_b_grid_infill_cells` remeasures T nonrectangular
  fragments64->12 and thin gaps37->0; other nonrectangular gaps remain open.
  Accepted corner/crossroads VMFs remain byte-identical. The earlier shaped
  build failed a missing-source identity check; corrected polygon serialization
  is not yet a completed all-family/all-yaw or compiled acceptance.
  Fresh ground53/infill68339/complex2843/straight568/geometry614/survey5662
  assertions and PowerShell8/8/diff checks pass. Actual generation emits the
  retained wall warning. No new visual/compiled review is claimed.

- **Alpha 3.2 measured-size infill / corrected corner accepted, 2026-10-13:**
  user approved the corrected corner, but reported remaining crossroads gaps.
  Measurements304/16/48units explain why whole320quarter fills were insufficient.
  User chose additional precisely sized editable bases. Explicit `-SizedInfill`
  creates missing rectangular patch sources only; artist edits are preserved.
  Corrected corner stays byte-identical and is not reopened. Seven new isolated
  previews under `generated/phase_b_sized_infill_cells` emit261ground owners;
  34editable sources total. Sized infill67550assertions require zero uncovered
  actual crossroads ground area across all324quarter regions, plus source/
  overlap/coverage preservation; straight568passes. Exact sized crossroads
  opened/responded in Hammer PID3760; user confirmed the cell is great.
  Corrected corner and crossroads ground/layout reviews are accepted; do not
  repeat them. Other nonrectangular fragments and compiled clearance remain gates.
  No normal generation/production/staging or costly batch authorization implied.

- **Alpha 3.2 Phase B Hammer review complete / editable infill active,
  2026-10-13:** user declared all original complete-cell Hammer checks complete;
  terminal/T/crossroads explicitly fine except missing ground. Do not reopen
  authored correctness/layout review. User chose320x640half/320x320quarter
  editable ground templates with plain generated bases for later artist detail.
  `create_terrain_infill_templates.ps1` creates missing sources only; never
  overwrite those artist-owned templates. `terrain_infill.psm1` separates
  ground-slab convex coverage from scenery leases, preserves underground
  footprints and fills fully empty quarter slots without scaling or Z changes.
  Seven corrected cells live separately in `generated/phase_b_infill_cells`,
  with91ground instances. Infill22345/complex2864/straight568/required7/7pass.
  Partial curved/fractional gaps, decorated-prop clearance and corrected visual/
  compiled review remain gates, not implied acceptance. Normal generation,
  motorway assets, production and runtime exports remain untouched.

- **Alpha 3.2 Phase B remaining whole-cell previews, 2026-10-13:**
  `build_motorway_cell_preview.ps1 -Complex` generates seven complete diagnostic
  cells under `generated/phase_b_complex_cells`: corner/crossroads/T/terminal/
  bridge/single/dual ramp, preserving approved straight fixtures. Six use real
  cells; T is explicitly synthetic because current world has none. Exact
  fractional XY/yaw/Z0, full shell/skybox, saved-winding leases across all rings
  and every-instance overlap diagnostics are fixture-covered. Complex2682/
  required7/7, straight568/geometry614/source-mouth5662/assembly1834pass.
  Existing bridge yaw90 exposes E/W measured motorway versus N/S source route;
  do not silently correct user-authoritative yaw or claim route support.
  Ordinary approaches, two-lane residuals, partial boundary tiles and terminal
  underlay remain unapproved diagnostics. Mixed corner/ramp and terminal/bridge
  cases reject explicitly instead of losing a route. Human whole-cell review
  and full Phase B acceptance remain pending; no compilation/staging/runtime/
  production changes. Continue from the exact gates in the tracker, not another
  individual-asset or approved-straight review.

- **Alpha 3.2 Phase B complete-cell examples approved, 2026-10-13:** user
  clarified that the preview must show motorway assets inside complete generated
  cells, not an assembly zoo. `bin/build_motorway_cell_preview.ps1` now drives
  the normal planner/builder's explicit isolated inspection mode for logical
  (6,-11) north-south and (2,-5) east-west straights. Full5760shell, scenery,
  border/outer rings and skybox room retained;27corridor leases/nine owners,
  64instances per cell. Fresh cell568/geometry614/source-mouth5662/assembly1834
  assertions and required2/2pass; normal-generation controls retain old family
  and origins. Both cells opened/responded in Hammer; user inspected both,
  confirmed they were fine and closed the editors deliberately. Do not reopen
  or diagnose a crash. This is scoped straight-cell visual acceptance, not
  whole Phase B. Complex-cell approach/clearance/topology work remains; no
  compile/staging/runtime/default settings or authored assets changed.
  See [the current tracker](docs/todo-alpha.3.2.md) for exact artifacts and limits.

- **Alpha 3.2 Phase B generated inspection gate, 2026-10-13:** continue-to-preview
  authorization produced an isolated overview plus eight four-rotation VMFs
  under `generated/phase_b_motorway`, through `bin/build_motorway_preview.ps1`.
  Hammer PID2288 is responding with the exact overview title; prior windows
  preserved. Geometry614/source-mouth5662/actual-preview1834assertions pass.
  Thirty-two cases separate40exact floor joins,32diagnostic joins and20pending
  road mouths. Diagnostic seams must never enter normal planner fallbacks.
  Fractional edges/grades/provenance, ring coverage and conservative overlap
  evidence are retained in the assembly report. Sources, settings, tuned plan
  and both installed runtime exports unchanged; no compilation/staging ran.
  Phase B is not complete/accepted: review generated joins, resolve measured
  approach/tolerance/clearance and topology gates in
  [the tracker](docs/todo-alpha.3.2.md). Do not re-open individual asset correctness
  or orientation approval; both remain user-authoritative.

- **Alpha 3.2 Phase B measured straight/bridge ports, 2026-10-13:** explicit
  source faces supply416-wide motorway floors Z68 at centres-512/+528 and
  bridge central-road floor width256/Z232.375 at X+/-960. Physical port
  transforms and horizontal translation solver preserve existing yaw/Z,
  rejecting type/width/heading/grade/deck mismatches exactly. Survey/port5245
  assertions and geometry614pass, source hashes unchanged. Algebraic seams,
  not compiled collision/driveability. Complex ports/approaches/clearances/
  layer-aware whole-cell fit remain next; no fallback ports, asset re-approval,
  planner wiring, regeneration or staging.

- **Alpha 3.2 Phase B rectangle helpers, 2026-10-13:** wide-only nominal
  footprint lookup, physical Source-yaw point/envelope transforms and explicit
  top-left-anchor slot reservations implemented.614assertions pass across all
  eight pieces/four rotations, including even-span half-tile alignment and
  actual unchanged1x1 planner yaw mappings. One emitting owner; overhang
  envelopes remain separate. No planner wiring, anchor solver, ring leases or
  collision-free assembly claim yet. Next is port/translation/layer-aware
  assembly work. User's authored trust/orientation decisions remain authoritative;
  no additional asset opening, geometry change, regeneration or staging.

- **Alpha 3.2 Phase B authored-trust decision, 2026-10-13:** user confirms their
  motorway assets are correct; do not request repeated individual-asset review.
  Measure ports/decks/envelopes for generator integration directly, preserving
  geometry. Hammer review is for generated assemblies or concrete integration
  ambiguity. Read-only winding survey covers eight sources;5214assertions pass,
  repeated report byte-identical. Straight floor Z68, centres-512/+528 (approved
  authored asymmetry); crossing road floor Z232.375. Coarse bounds/overhangs
  are evidence, not compiled collision/verified ports. Bridge editor launch
  reports Error and is not visual evidence; no further asset opening requested.
  Source registry/rotations/reservations remain next. Phase B incomplete; no
  builds/staging/settings or geometry edits.
  User further confirms all new orientations match their1x1 counterparts in
  every circumstance. Existing topology/yaw mappings are authoritative; no
  orientation guessing, correction or repeated human approval is needed.
  Measure only changed footprint/port/deck/offset integration data.

- **Alpha 3.2 Phase A accepted / Phase B survey next, 2026-10-13:** new manifest
  exports resolve/store density version/tier/source/inland distance and exact
  building alias. Planner consumes stored values for recipes/variants and
  preserves records; runtime export rejects manifest/plan mismatch. Legacy
  manifests retain prior policy with a planner warning; no in-place upgrade.
  Fresh density2384assertions include actual serializer/reload144-cell fixture,
  corrupt/legacy/header checks and production density consumers. Existing
  skyscraper regression passes. Settings/tuned-plan/city-runtime hashes unchanged.
  User accepted Phase A on scoped source/fixture evidence. No regeneration/
  compile/staging occurred; D/E/G still own placement and physical integration.
  Next is the Phase B authored motorway connector survey. No new geometry or
  compiled-world acceptance is implied.

- **Alpha 3.2 Phase 0 accepted / Phase A active, 2026-10-13:** user continued
  after checks/baseline approval. Density policy approved: cardinal land steps
  from actual ocean,0-2 protected low/3-7 medium/8+high; commercial/financial
  raise inland to high, settlement at least medium, coast wins. Approved small
  fixture recorded in [the tracker](docs/todo-alpha.3.2.md). Pure classifier/zoning/
  roll/hash/pool module passes1490focused assertions across88authored templates,
  including exact roll thresholds and pinned hash/locale reproducibility,
  without normal generator imports or output changes. Settings/tuned-plan
  hashes unchanged. Authoritative field/legacy alias wiring remains
  next in A; placement pools and widened-route adjacency follow D/E. Phase A
  remains incomplete; no expensive integration work is authorized.

- **Alpha 3.2 Phase 0 checks complete, 2026-10-13:** GLua271/0 and existing
  tuned-plan variety4807assertions pass (576cells/311recipes/1104pairs).
  Main GMod process verified with `-disableluarefresh`; fresh preview launcher
  atmosphere/screenshot and read-only persistence evidence retained. User
  approved the existing Home presentation baseline. No deployment, settings/
  lighting change, generation or staging ran. Phase0 checklist complete;
  whole-phase acceptance remains separate. Next is Phase A density contract
  after acceptance, not CSM or carried 3.1.5 closure. Earlier closed-game/pending
  baseline notes below are superseded by this live evidence.

- **Alpha 3.2 Phase 0 started, 2026-10-13:** user authorized readiness/inventory
  after archiving [Alpha 3.1.5](docs/todo-alpha.3.1.5.md). Read-only inventory
  hashed158VMFs; current tuned311-recipe/576-cell plan and manifest match staged
  preview runtime hashes. All16 original restoration backups verify; the5854
  ledger entries have not undergone a new full staged-output audit. Thirteen
  stale configured asset references and32orphanVMXs remain; preserve sources.
  The border `1bb` extension is now correct; user approved renaming the industry
  typo to `tile_industrial_3aaa.vmf` (high density), with geometry unchanged.
  GMod is closed, so current
  player state, native lighting baseline and running watcher-free evidence
  remain pending. Phase0 is not accepted; no builds or source geometry changed.

- **Active milestone: Alpha 3.2, generator-first scheduling, 2026-10-13.**
  The user moved unfinished Alpha 3.1.5 Phase D output acceptance and Phase I
  integration to the end of [the 3.2 master plan](docs/todo-alpha.3.2.md):
  J bundles final-revision outputs; K owns carried closure/acceptance/restoration.
  They are not prerequisites to generator work and are not accepted by transfer.
  Execute 0/A/B/D/E/F/G (generator), then C/H/I (CSM/integration), then J/K/L
  (shared outputs, carried closure, documentation/acceptance). Implementation
  remains pending; this scheduling change authorizes no expensive build, staging,
  production or publication. Accepted 3.1.5 phases/limits remain unchanged;
  newly authored safe-zone detail work remains deferred. Earlier active/next
  phase notes below are chronology superseded by this scheduling decision.

- **Expensive-work batching preference, retained from 2026-10-12:** prioritize
  fast source edits, focused fixtures and bounded live checks. Ask before any
  considerable process, including preview/world regeneration, VBSP/VVIS/VRAD,
  navmesh generation, full material/Satellite generation or other large staged
  jobs. Bundle those expensive activities into one later approved pass where
  dependencies allow; do not start them opportunistically.

- **Phase D acceptance deferred / Phase E source work authorized, 2026-10-12:**
  user explicitly chose to defer Phase D's expensive output batch and continue
  source-only Phase E implementation. Do not infer Phase D acceptance or run
  its complete preview materials/wireframes, navmesh refresh or576-cell
  two-variant Satellite capture. Phase E source edits and focused fast fixtures
  are authorized; bundle expensive integration work later after asking.

- **Phase E accepted / Phase F active, 2026-10-12:**
  movement scales are0.675/0.765 with stamina unchanged. Searchable activation is
  halved once, active centres use deterministic priority and320-unit 3D spacing,
  and new body generations use1-2 while unexpired legacy generations retain2-4.
  Loot cells track content-hashed map filenames; a changed known fingerprint
  atomically backs up and resets only that profile/logical cell once, while old
  metadata-less rows are baselined unchanged. Matching old-map backups can be
  restored with their old spot rows. Fresh movement5/5, loot12/12,
  loot-spots18/18, enemy14/14, boss5/5, foliage16/16 and GLua266/0 pass.
  Fault-injected reset failure retains old rows and commits no backup. The user
  initial live review found no searchable loot because the new revision helpers
  were accidentally nested inside the first loot replacement and therefore
  absent on a real fingerprinted cold start. Helpers now load at file scope; the
  first fixture covers that exact path. Fresh loot-spots19/19 passes, live cell423
  exposes7 active spots from79 candidates, and the user confirmed highlighting
  and searching work. Phase E is accepted. Phase F server snapshots are active;
  defer client thumbnail rendering until isolation/idempotence is proven.

- **Phase F first server snapshot slice, 2026-10-12:** owner/profile-filtered
  character listings now include decoded appearance, worn shirt/pants, selected
  weapon visual, validated city/den/start location and a stable presentation
  revision while stripping internal character IDs. Two-call fixtures prove source
  character/data/inventory/weapon rows unchanged and slots isolated. Fresh
  characters11/11, inventory51/51 and GLua266/0 pass. Add explicit den/corrupt/
  appearance-required cases before beginning the bounded client thumbnail cache.

- **Phase F accepted / Phase G prototype gate active, 2026-10-12:**
  snapshots now cover city/den/start/corrupt location, clothing, selected weapon
  and stable revision without exposing ids or mutating source rows. Client cards
  bound three visible panels/one in-flight build, retry transient clothing
  failures, release materials/models/queues and restore the page after fixtures.
  Aspect-aware renderer-v2 framing fixes torso/head cropping; icon-model fallback
  displays Jim's crowbar without a SWEP. A live fixture exposed forged profession
  fallback and wrote `Valid Test` to slot1; strict `GetKnown` validation and an
  explicit-owner test writer fix the cause. Both fixture rows were transactionally
  removed and slot1 is empty; no cleanup command remains. Fresh characters12/12,
  inventory51/51, professions12/12, cards2/2 and GLua268/0 pass. Direct captures
  show Jim full-body/clothed with crowbar, CITY15,5, empty slots1/3 and unchanged
  Earth before/after cleanup. The user accepted Phase F on this evidence; no
  second real survivor or legacy slot was fabricated, and that unavailable
  comparison remains a validation limit. Phase G begins at its prototype gate:
  settle the exact Earth/distress asset source, then build only one Earth and one
  selected-cell city example before appearance/performance approval and broader
  polish. Do not substitute the Phase H supplied logo.

- **Phase H accepted / Phase I active, 2026-10-12:**
  user approved Natural Earth public-domain base art after licence review.
  `build_launcher_earth.ps1` pins the reviewed source and owns five layers plus
  one shipped notice: day, generated night lights/clouds/distress/rim. Static
  low/high Earth pairs are960/3968 triangles; one presentation owner switches
  Earth/city/hidden. The city example resolves Jim's exact preview15,5 skyline
  model with one model/marker/label; active-slot default is read-only. High,
  close, low and city direct captures exist. GLua271/0, presentation server3/3,
  client2/2, characters12/12 and packaging62/62 pass; launcher notices pass
  while whole launcher6/7 retains the unrelated changelog-order failure. Reject
  the first cold full-layer sample (384.70ms hook); warmed high is0.0264ms/hook,
  ~1.03KiB/frame and16.64ms median, but p95/p99 are49.59/52.00ms and matched
  city median is49.97ms under background throttling. This is operation evidence,
  not performance acceptance. The user then reported severe live lag while
  otherwise approving the presentation. The city owner was reparsing the full
  world and skyline JSON every rendered frame: a focused control measured
  399.38ms and12.04MiB/frame. Profile-cached assets and a selection/revision-keyed
  model cache reduce that same hook to0.0856ms and1.71KiB/frame; focused client
  tests pass3/3 and repeated Earth/city switches retain one asset load. High/
  normal Earth/layer3 is restored. The user confirmed both Earth and city are
  smooth in the foreground and accepted the remaining presentation. Phase G is
  accepted; the background-throttled samples remain scoped evidence rather than
  a clean60FPS measurement. Phase H now has an explicit page-to-state owner and
  exactly four Home actions: Play, Tools, Settings and Exit. Play opens survivor
  selection without deploying; Content Addons/Credits moved under Settings.
  Fresh launcher presentation4/4 and GLua271/0 pass; direct capture confirms the
  new Home composition. Phase H camera choreography, card-grid layout, manual
  Earth controls and human visual acceptance remain open.
  The next Phase H slice adds timer-free4.5-second Home-to-Play and3-second
  Play-to-Home presentation handoffs in the existing sole render hook. The user
  rejected both a crossfade-only handoff and skyline geometry attached to the
  globe. The approved direction is staged: Earth alone zooms1x->3.6x toward the
  selected coordinates, fades out, then a separate grounded sunset horizon fades
  in. Its bounded3x3 logical-cell cluster currently owns12 dark silhouette models,
  a warm backlight sun, haze and a ground plane. Mid-flight Back/page changes
  retain current weights/zoom without stale timers. Fresh presentation server3/3,
  client5/5 and GLua271/0 pass; horizon hook0.1395ms/frame,4.52KiB/frame. Human
  horizon/choreography review, selection retarget and resize/cancel remain open.
  The exact supplied transparent288x128 `logo.png` is now staged once under the
  launcher UI materials and replaces the temporary Home text heading. It retains
  its aspect/transparency inside bounded breathing/grunge framing; material
  dimensions are covered by the focused client suite. Fresh direct capture,
  presentation5/5, GLua271/0 and packaging62/62 pass. Human logo/framing approval
  remains a Phase H visual gate.
  The user then replaced the preview launcher's enclosed starfield brushes with
  real `tools/toolsskybox` windows around the authored scale16 3D-skybox room.
  Source now adds the map-owned `launcher_presentation_skybox` marker beside its
  `sky_camera`; server status sends that anchor/scale, and the sole presentation
  hook transforms Earth, the skyline cluster, sun, haze, ground, marker and label
  into the engine skybox pass. Launchers without the marker retain the prior
  world-space path, so the unchanged city launcher is not opted in accidentally.
  GLua271/0 and diff checks pass. The preview launcher BSP has not been rebuilt;
  actual skybox placement, transition appearance and performance remain live
  gates, and the expensive-work batching preference still applies.
  The user approved the skybox-backed Earth after the isolated preview launcher
  passed VBSP/VVIS/VRAD and a full Source-cache-clearing restart. Fresh client
  presentation6/6 passes; the sole hook measures0.0356ms and1.26KiB/frame with a
  0.1186ms maximum in the five-second sample. The user next requested that normal
  launcher presentation hide the authored preview water and look more like
  space, while sky inspection must retain its water and selected-sky behavior.
  The first runtime full-sphere mask was rejected after an actual1.1FPS warm
  sample; it was removed completely. The replacement is source-owned: only the
  29 water faces across 3D-skybox brushes4048-4056 are nodraw, while the six
  main-world inspection-water faces remain unchanged. Home/Play use approved
  `imported_tropo_night_2` through the existing cached sky-palette meshes;
  inspection still owns its selected sky/fog. Preview launcher
  VBSP/VVIS/VRAD passes and both staged BSPs hash
  `5A9CE06B755EE2B7B85C855A7446AA1A9716BB0A4E1D63C1C01F615638DC7242`.
  Fresh client presentation7/7 and GLua271/0 pass. Human no-water/space review
  remains open because the user reported rising paged memory during the check.
  The user then rejected the scale-only globe zoom, missing city marker, floating
  skyline treatment and cluttered survivor-card layout. Phase H now has one
  continuous descent value: a pulsing geographic marker follows the same Earth
  rotation, the marked globe grows and drops past the view, a bounded atmospheric
  veil owns the scene handoff, and a separate destination resolves through that
  veil.   The destination is a cached1344-triangle enlarged rolling-terrain mesh plus a
  96-triangle road cross with the existing bounded12-model skyline cluster seated
  at terrain height and rendered with its authored materials. A far ridge keeps
  the ground boundary out of frame, and the atmosphere-covered handoff swaps from
  the approved night sky to matching daylight before the destination appears. It
  is no longer a flat black silhouette. The Play UI is now one three-slot horizontal selector
  plus one selected-survivor dossier rather than three vertically interleaved
  cards. Ruled metadata, a bordered/backgrounded286px portrait, explicit equipped
  weapon stack, face-safe headroom and subordinate Delete action reduce clutter
  without changing explicit Deploy ownership. Each equipped weapon has a labelled
  icon box; the old posed model and duplicate equipped strip are removed. Fresh
  GLua271/0, client presentation8/8, character cards2/2 and characters12/12 pass.
  A five-second city sample measured59.74FPS,
  0.08345ms/4.91KiB per presentation-hook frame, two diorama meshes,12 city
  models and -147.98KiB retained Lua heap. Marker/descent/diorama/card appearance
  then received human approval in the running preview launcher. The subsequent
  enlarged daylight destination, smoother veil handoff and multi-weapon boxes
  also received explicit human approval. Keep this choreography, grounded
  destination and card treatment. The remaining Phase H lifecycle/manual-control
  gates are separate; Phase H remains unaccepted.
  Home now owns a transparent right-viewport Earth control surface: left-drag
  rotates, the wheel zooms within camera-distance-derived0.72x-1.65x bounds, and
  Reset View returns to the saved city anchor without changing gameplay data.
  Input is unavailable during transitions and outside Home; page/inspection/
  frame ownership changes release capture and smoothly return zoom to1x. Fresh
  GLua271/0 and launcher presentation10/10 pass. The user approved drag, zoom,
  Reset View and Play/Back mouse cleanup in the running launcher. Resize and
  Tools/browser/credits/appearance round-trip cleanup remain unverified.
  Create Back now walks prior wizard steps and returns from its first editable
  step to the survivor grid rather than Home; legacy appearance cancel also
  returns to the grid. Page switches release Earth input synchronously. The
  focused client lifecycle case covers these owners without creating, deleting
  or deploying a survivor.
  The user then approved Settings/Back, Tools/Back, Create cancel and Credits
  exit with normal mouse/camera restoration. Request ownership now remembers
  its initiating page: content failure retains the survivor-grid Back target,
  while a timeout returns to the grid instead of Home. Fresh launcher
  presentation11/11 and GLua271/0 pass. Typed-delete cancel, actual server
  failure, Exit confirmation and both-profile availability remain open.
  Tools visibility is now separate from preview-only action availability. The
  city launcher exposes Item Atlas, Content Status and Sky Browser; Map Atlas
  remains disabled because its inspection path is still preview-hardcoded, and
  Wardrobe retains its preview-admin guard. Actual-client profile tests pass1/1
  in city and1/1 after the verified return to `zn_preview_start`/preview. The
  broader both-profile Settings/admin review remains open.
  The user also approved typed-delete dialog cancel and Exit-to-GMod cancel:
  both return to the correct launcher page with normal mouse/camera ownership.
  No survivor was deleted and disconnect confirmation was not executed.
  Empty-grid rendering and explicit server rejection are now fixture-covered:
  three empty slots expose Create only, and rejection/timeout retain their
  initiating grid and reason. Launcher presentation12/12 and GLua271/0 pass.
  A five-second daylight-destination operation sample measured0.21527ms and
  9.15KiB per presentation-hook frame (1.454ms max;34.25KiB retained heap).
  Its19.74FPS process average is background/unmatched and is not performance
  acceptance or a regression comparison; Earth presentation was restored.
  The user accepted Phase H with the explicitly retained limits: destructive
  delete/disconnect confirmation, live city Settings, resolution-change review
  and matched foreground performance were not required to repeat or fabricate.
  Proceed to Phase I integration planning. Do not start the complete preview
  closure, navmesh, Satellite capture, city rebuild or publication until the
  user separately approves the bundled expensive work.
  Phase I's previously retained launcher-suite failure is resolved: current
  3.1.5 and archived3.1.0 changelog highlights now follow the required
  additions/limits/fixes grouping, including removal of one accidental leading
  space and stale “planned Earth-to-city” wording. Fresh launcher Tools8/8
  passes; this is data-order cleanup, not new historical claims.

- **Paged-memory investigation, 2026-10-12:** pausing stops the observed commit
  growth, narrowing it to active frame/tick work. Two early idle windows rose
  6.44MiB and12MiB, but a matched settled60-second run then rose only2.47MiB,
  entirely in the first10seconds before plateauing; working set fell8.13MiB.
  Development-only profiler GC boundaries show114KiB retained Lua heap across
  2101frames, with bounded23 client entities, zero city models, one sphere, six
  palette meshes and zero card entries. Ten Earth/city cycles incurred one
  approximately9MiB Source model/material cache admission, then private commit
  remained exactly2373.67MiB for every cycle; handles were unchanged and retained
  Lua heap was76.3KiB. This is evidence of allocator/cache high-water behavior,
  not an idle or launcher-cycle live-object leak. It is not proof that every
  deployed gameplay subsystem is leak-free; representative long gameplay remains
  a separate diagnostic if growth continues outside the launcher.

- **Phase C accepted / Phase D active, 2026-10-12:** the user confirmed blocked
  red and waypoint-yellow arrows render correctly and that all tested gate
  entries and exits work after the motorway arrival correction. This completes
  the remaining Phase C live colour, travel, arrival and regression review.
  Phase C is accepted on the accumulated static, compiled-map and live evidence;
  earlier `Phase C is not accepted` notes below are historical and superseded.
  Proceed to Phase D full-footprint minimap, world artwork and revision-matching
  Satellite capture. Production rebuilds and publication remain separately
  gated, and the deferred safe-zone entrance/detail walls remain untouched.

- **Phase D full-footprint projection, 2026-10-12:** audit found the Level/
  minimap capture still used an old camera/FOV-derived ~3206-unit span while
  revision-matching world capture already used the authoritative5760 pitch.
  `world_capture/sh_contract.lua` now owns local-map span/projection; city
  captures use `ZM_World:GetCellBounds().neighbourPitch`, den span remains
  independent, and cache version11 invalidates cropped captures. Offline
  capture client7/7 and server7/7 cover centre,+/-1600,+/-2240,+/-2880, all
  cardinals, asymmetric coast/land extents and den isolation; GLua266/0.
  Fresh `zz_preview_a0e68fbdcfc2-edge2` reload retained preview with no recent
  Lua/capture error. User confirmed the fresh Level/map-texture view shows the
  complete outer footprint and player/loot/door/gate-arrow markers remain
  aligned. Current-cell Level/minimap projection is accepted; stitched world
  previews, fresh Satellite imagery and den capture remain Phase D gates.

- **Phase D artwork/HUD source pass, 2026-10-12:** respecting the expensive-work
  batching preference, no world/material generation, compilation, navmesh or
  Satellite job ran. Cell artwork now consumes matching generated layout
  metadata in an authoritative9x9 frame: inset5x5 core, actual border/outer
  placements and water for omitted ocean bands. Wireframes use neighbourPitch/2
  rather than1640; static HUD texture projection and cross-cell compass use the
  authoritative pitch, while den map view retains its old independent height.
  New focused artwork fixture passes core/environment, border route, outer edge
  and west-ocean cases. Tuned-plan dry run validates311 layouts; wireframe dry
  run validates576 cells at5760 span. Capture client7/7/server7/7 and GLua266/0
  pass. The multi-tile suite was stopped when it exceeded the quick-check
  window; rerun it in the later approved validation batch. Fresh generated/
  stitched/wireframe materials, navmeshes and Satellite imagery remain pending.

- **Preview variety/rebuild side task, 2026-10-12:** user approved a future
  48x48 city (preview stays24x24), neighbour-aware recipe variants,
  and excluding aaa straight-wall pieces immediately beside road/motorway
  corridors in both rings. Full preview regeneration is authorized using all
  current authored edge walls/renames. Only the new safe-zone detail placement
  and design plan remain deferred; this supersedes the older committed-only
  tile restriction for this rebuild. Work is isolated under
  `generated/preview_variety_tuned_20261012`; production rebuild/publication
  remain unauthorized. User rejected the initial eight-variant495-map pool as
  too large and requested tuning with neighbour avoidance retained. Its
  compiler/continuation processes were stopped; do not resume/stage that build
  under `generated/preview_variety_20261012`. New policy caps candidates at4,
  retains infrequent base layouts unless adjacency requires an alternative,
  and scales frequent pools by ceil(uses/15). Tuned preview311 recipes plus3
  dens (314maps);11720 assertions pass; all1104 cardinal pairs differ in
  filenames and actual tile layouts.387/576 cells retain their base layout.
  Current-source build complete:VBSP/VVIS/VRAD314/314, no failures/incomplete;
  portals314/314, compiled818gates/818arrivals, skyline311recipes/runtime576cells.
  Tuned full-layout checks13896 assertions pass. Staged with GMod closed and
  verified4264 content/engine paths;16 original backups verified in extended
  Phase B restoration ledger. Old captures preserved/incompatible. Launched
  `zn_preview_start` for fresh review; deployed gameplay/visual acceptance pending.
  Edge corner VMX renamed to match its VMF, byte-identical content preserved.
  Phase C is not accepted; production/publication remain untouched.

- **Development-environment lag finding, 2026-10-12:** the staged tuned preview
  reproduced severe stalls with growing non-paged kernel memory (FMic/Irp tags
  to1.77GiB). A matched same-map/cell/weather A/B isolated the trigger to GMod
  Lua autorefresh watching this in-place development tree (120815 files;
  `generated` alone72859files/30.5GiB). Normal launch:45.23FPS, frame p95
  54.16ms, pool growing. Documented `-disableluarefresh` launch flag:56.34FPS,
  p9520.73ms, pool stable ~0.55GiB. Client Lua hooks were identical
  (4.17 vs4.18ms/frame), and the same gamemode file I/O ran in both, so
  ZombieSim runtime code is not the allocation owner. Released players are not
  expected to reproduce it: `generated/` is gitignored/outside the release
  allowlist and packaging ships mounted `.gma` archives rather than loose
  watched files. This is architectural reasoning plus the A/B, **not** a
  measured clean packaged-install run, and the owning Windows filter/driver
  remains unidentified; user chose to record it rather than test further.
  Launch defaults, Steam preferences and gameplay code are unchanged. Treat
  autorefresh-enabled samples as unrepresentative of player performance; use
  watcher-free matched runs for any future performance acceptance.

- **Phase C motorway arrival fix, 2026-10-12:** live travel showed gate arrivals
  placing the survivor inside the motorway concrete central reservation.
  `bin/transition_gates.psm1` writes every `<SIDE>_ENTRANCE` landmark on the
  cell axis (cross-axis 0), and `tiletemplates/roads/tile_motorway.vmf` has a
  median barrier at x-8..8, z40..48. Phase C had moved the arrows onto the
  carriageways but never the arrival. Fixed at runtime in `sv_transitions.lua`
  (`ResolveGateArrivalPosition`), not in the generator, so no map rebuild was
  needed: motorway arrivals trace the right-hand carriageway at lateral160,
  384 inward -128 past the arrows - and validate the player hull before
  placing. Ordinary roads, den exits, unsupported surfaces and an obstructed
  carriageway keep the authored landmark. User requested and approved this
  placement, including spawning behind the arrows. Measured motorway section:
  carriageways x-256..-16 and16..256 (centres+/-136), outer walls+/-264..280.
  Arrows, arrival yaw,160u/s walk and fade timing are unchanged. Offline
  server transition markers8/8 (two new cases), client10/10, GLua266/0; live
  reload republished both gates as motorway pairs and the user confirmed the
  corrected arrival in `zz_preview_a0e68fbdcfc2-edge2`. The authored landmarks
  themselves are still median-centred, so a future generator correction remains
  open; the runtime fix is the current contract. Phase C is not accepted.

- **Phase C continuation, 2026-10-11:** user deferred newly authored safe-zone
  entrance/detail walls and their new design plan; preserve those working assets.
  Isolated committed `7d7f8501` tiles under `generated/phase_c_live_20261011`
  keep them out of gate regeneration. Fresh outer2306/client markers10/server6/
  catalogue2 pass; original Phase B backups2074/2074 verify. Full isolated
  preview retains576 cells/187 recipes, no logical recipe mapping changes,
  190 VMFs including dens, zero missing. VBSP190/190 and all portal budgets pass;
  skyline187 recipes complete. Compiled gate check186 maps/484 gates/484 arrivals
  passes. Isolated VVIS/VRAD running, export follows successful completion;
  not staged or live accepted. GMod was closed at the status probe.
  Preserve completed captures; new gate geometry requires a new capture revision,
  so old Satellite must remain compatibility-gated after staging.

- **Imported assets and notices side task, 2026-10-10:** user-confirmed creator
  permission covers the five exact supplied GameBanana archives; no independent
  license text was supplied. Added hammer/machete/spanner/Lewis and radiation-suit
  HEV Gordon/hands, preserving saved appearance. Approved hammer-only world
  derivation and mounted CSS sleeve substitution; no archive Lua installed.
  `bin/import_assets.py` now owns all six imported sources and 1768 files through
  `content/data_static/imported_assets.json`; original CS 1.6/machete credits
  remain. Missing CS 1.6 ZIP uses verified retained ownership, not a fresh archive
  validation. Arsenal55 ranged/four melee; quartermaster32 offers.
  Options Third Party Licenses follows Changelog and displays35 sky/six asset
  records with original text and explicit permission-only notices. Shared scroll
  sizing includes both footer buttons and bottom padding in launcher/gameplay.
  GLua265/0, offline9 pass/one missing-source skip; fresh imported server3/3,
  client5/5, catalogue55/0, effects20/20, static18/18, inventory51/51, loot12/12,
  trading14/14. Fresh notice content/lifecycle/measured padding case passes;
  whole launcher suite6/7 retains an unrelated changelog source-order assertion
  failure (3.1.5/3.1.0 highlights). User confirmed corrected launcher footer
  fully visible. Packaging61/61; report-only audit8367 files/six packages/
  707 existing release blockers. User also approved notice readability,
  scrolling and closing back to launcher Options. Human weapon
  appearance/manual firing remain unverified. No Phase C acceptance or upload.

- **Weapon side task, 2026-10-10:** the approved arsenal now contains 24 CSS
  firearms, 24 CS 1.6 variants and six HL2 ranged weapons. CS 1.6 is loot-only
  at exactly 1/100 counterpart weight; fixed +25% damage/+20% range and
  capacity/15% faster firing and reloads compose with random/mastercraft
  scales. Keep these independent item IDs and existing offers intact.
  Offline weapons6/6, GLua257/0, packaging59/59; fresh preview catalogue54/0,
  effects20/20, static18/18, inventory51/51, loot12/12 and trading14/14 pass.
  Actual isolated crossbow projectile damage/lifetime tests pass; human
  weapon/hands/audio appearance and survivor firing remain unverified.
  Explosives, alternate fire, gravity gun and recoverable bolts are excluded.
  This side task does not accept Phase C or authorize publication.

- **Alpha 3.2 scope**, designated on 2026-10-10 and expanded in the
  user-approved planning decisions on 2026-10-13. Follow the
  [master phased plan](docs/todo-alpha.3.2.md) for density-aware buildings,
  decorations, borders/edges and footprint-aware 3-wide motorways, plus the
  [CSM technical tracker](docs/csm-implementation.md). The 2026-10-13 user
  scheduling decision makes generator work the priority and carries 3.1.5
  closure to final phases J/K, without running implementation or builds.
  On 2026-10-14 the user explicitly accepted an additive client-local CSM
  overlay, superseding the earlier replacement-quality requirement. Leave baked
  `light_environment`, lightmaps and shared server state untouched; preserve an
  exact native path when CSM is off, keep the default off, and review additive
  brightness/overlap, performance and multi-client behavior. Production
  rebuilds and publication remain separately gated.

- **Fixture-review preference:** when the user chooses to inspect fixtures,
  open the exact requested VMFs in the installed Hammer++ for them; do not
  merely provide paths or ask them to find the files. Identify which opened
  fixture covers each review case. Preserve unsaved editor work and do not
  treat opening a fixture as visual acceptance.

- **Historical Alpha 3.1.5 implementation:** see its
  [archived tracker](docs/todo-alpha.3.1.5.md); unfinished closure moved to 3.2 J/K.
  The user authorized
  implementation on 2026-10-06 after adding the edge tiles. Phase 0 is accepted:
  nine edge sources inventoried, current 179-recipe baseline and verified
  restoration copies retained, focused launcher baseline captured. User carried
  coast/gate photographs and full quality/cold-warm baseline into A/B/G; do not
  reopen Phase 0 for those limits. Preserve approved source overhangs.
  **Phases A/B/C are accepted; Phase D is in progress**, then follow Phases E-I in order. Shared bounds,
  deterministic outer-ring generation and layout metadata are implemented but
  disabled in normal settings. Isolated checks: outer edges 519 assertions,
  GLua 184/0, border showcase/entrances pass, ten VBSP/portal fixtures pass,
  BSP entity checks retain 287 corrected dynamic props, live bounds 6/6 in the
  preview launcher. Human confirmed north-facing straights and NW-opening
  corners, and approved class-only correction of 15 incompatible new-edge
  trees/signs; original brush/prop placement and overhangs are unchanged.
  User accepted both land/coast Hammer fixtures on 2026-10-06 after the agent
  opened them in Hammer++; the user closed the editor windows after review.
  User subsequently accepted both enlarged land/coast in-game geometry
  reviews in Sandbox. Two isolated BSPs completed VVIS/VRAD without failures;
  temporary runtime copies were removed after verified return to
  `zn_preview_start`/preview. Before/after city and preview survivor persistence
  snapshots match exactly; live bounds remain 6/6. This is geometry acceptance,
  not integrated ZombieSim pursuit, loot, skyline or gate acceptance.
  **Phase A is accepted**; the user authorized Phase B on 2026-10-06,
  carrying integrated pursuit/loot/gate checks into later phases. Generated
  fixture sources/zoos are under `generated/outer_edges`; no enlarged maps,
  skyline or runtime exports staged. Gates/transition-road blocking geometry
  still require the planned Phase C migration. Preview-first; production
  city rebuilds and Workshop publication require separate approval. The supplied
  logo, exact globe asset clearance and live baseline gaps are explicit gates,
  not permission to guess. No phase is accepted solely by static checks.
- Phase B source/isolation checks now pass: shared 5760 pitch, schema-2
  plan/bounds/coast compatibility, recursive source hashes and complete model
  companion caches. User explicitly retained the original procedural beach
  beyond the 2240 coast edge; do not replace it with a water-only strip.
  Six isolated skyline fixtures: 177 assertions, manifest/tower/height pass,
  VBSP/portals 417/1317 maximum; installed legacy manifest 179 recipes still
  passes. GLua186/0, fresh isolated geometry8/8, packaging57/57.
  `generated/skybox_edges` contains models/room/VMFs/reports; none staged.
  Fresh expanded renderer visuals and matched performance remain Phase B
  gates. Launcher reloads verified logic only, not renderer appearance.
- **Phase B accepted 2026-10-09:** user confirmed the edges worked perfectly and
  accepted remaining live/review gates on accumulated in-game review. Do not
  reopen historical dense/coast/bridge/snow/tower/fire checks or matched
  performance merely to fill gaps. Uncaptured cases are retained limits, not
  fabricated test evidence or a performance verdict. Proceed with Phase C
  gate/arrival/road-arrow migration; it is not pre-accepted. Temporary expanded
  preview assets remain ledger-owned for continuation; return/restoration
  obligations and production/publication gates remain unchanged. This acceptance
  supersedes the earlier Phase B pending/unaccepted notes below.
- **Phase C runtime arrows 2026-10-10:** single arrows are visible after a
  controlled two-sided/depth-tested material correction. User requested two
  motorway arrows at the annotated carriageways rather than the median.
  Each motorway arrow has its own server surface trace at+/-160 lateral,
  256 inward; ordinary roads retain one96 inward. World-data classification
  waits for GM profile initialization and cleanup republishes. Offline client8/8,
  server6/6, GLua200/0 and fresh actual-client8/8 pass. Preview15,5 capture shows
  N/S pairs on deck36 and E/W singles on bridge196. User approved revised-pair
  placement; live colours/range and integrated travel remain gates. No new Phase C maps or
  generated runtime exports staged; temporary Phase B restoration remains due.
- **Phase C map-arrow integration 2026-10-10:** HUD minimap (live/texture) and
  satellite/Level view use dynamic clipped projections of the same gate anchors
  and colours, not baked capture arrows. World-map window/waypoint diamond are
  unchanged. Offline/fresh actual-client10/10, GLua200/0, editor diagnostics and
  human review of both views pass. Actual yellow/red state and integrated travel
  remain unverified; Phase C is not accepted.
- **Captured-world side task 2026-10-10:** user authorized the resumable preview
  capture/import pipeline and combined navmesh/capture maintenance before
  returning to Alpha 3.1.5. See `docs/world-capture.md`. Player Atlas now refers
  to existing illustrated Satellite assets; old layered Atlas is retired only
  from the selector. New Satellite is complete captured imagery, never a partial
  or stale collection. Map/Level, Walkers, Wireframe and launcher Map Atlas stay
  separate. Cubemap native command is Lua-blocked; do not bypass via aliases,
  exec or RCON. Actual capture capability/adjacency/restoration and composite
  nav checks remain gates, not accepted merely by fixture tests.
- **Capture pilot verified 2026-10-10:** revision4 now uses skyline-owner camera
  height4992 with native sky/capture-scoped coast; prior black buffers rejected.
  Seven logical cells/14 outputs plus separate Storm Drain2/2 pass; composite
  generated/saved/reloaded1313 NAV areas before two captures. Survivor restoration
  verified at preview15,5. Partial256px tiles/3072px overview staged with explicit
  incomplete manifest,1.81MB encoded/75.5MiB estimated RGBA; Satellite remains
  disabled. Client6/6,server6/6,importer5/5,atmosphere17/17,GLua208/0.
  User approved pilot imagery and authorized full preview capture rollout;
  full-world completion/import remains pending.
  active Alpha3.1.5 Phase C remains unaccepted.
- **Phase C first source boundary 2026-10-09:** bounds-driven expanded gates now
  use+/-2208, with corresponding inward arrival landmarks. Canonical road/bridge
  deck extraction yields36/196 and lifts elevated triggers/barricades/arrivals
  by160; no authored tile edits. Expanded old blocking transition-road variants
  become ordinary straight roads; bridge/core/coast/other-border transforms are
  protected. Isolated outer2306, original border/entrance suites and13 VBSP/portal
  fixtures pass. Nothing newly staged; arrows and integrated travel remain next.
  Phase C is not accepted. Running assets still belong to the Phase B ledger.
- **Coast clarification 2026-10-07:** the requested fixture is the Storm Drain
  grid `(0,12)` / logical `(0,0)`, not the SE authored water-corner fixture.
  Omit new outer scenery only along the west 3D-skybox ocean; preserve all old
  border and water-corner tiles. `skyboxOceanSides` drives omission/renderer
  attachment separately from `waterBorderSides`. West recipes use
  `-oceanw-edge2`; expanded preview187 recipes vs unchanged legacy179.
  Exact Storm Drain has21 unchanged border pieces,23 outer pieces,zero west
  outer pieces. West skybox shoreline attaches at-2240, not-2880; its640-unit
  band fills the gap while retaining the approved beach. Skyline275 assertions/
  eight recipes, outer1158/exact old source transforms, original border/entrance
  suites and VBSP/portals474/1517 pass. New no-gap live case not run
  because game closed; expanded visual review remains pending. Do not stage
  or treat earlier SE-corner review as approval of this corrected coast.
- **Physical coast shell correction 2026-10-09:** the Hammer black strip was
  traced to uniform shell expansion: the floor and sky wall still reached 3072
  past the west border even though outer tiles were omitted. The shell now
  consumes `skyboxOceanSides` and retains the original 2240 ocean boundary.
  Land-facing clearance, clips, ceiling, old border/core instances and beach
  remain unchanged. Earlier renderer-coordinate checks did not prove the
  physical connection. Fresh outer regression1796/skyline331 assertions and
  eight VBSP/portal fixtures pass (max474/1517; Storm Drain363/1109).
  Existing sky_day01_01 texture-size/flags diagnostic is unchanged from the
  retained baseline. Corrected fixture opened separately in Hammer++ under
  `generated/coast_shell_fix/skyline/src`; original window preserved.
  User confirmed the black strip is gone in the corrected Hammer fixture.
  Integrated beach/ocean renderer appearance remains unverified.
- **Phase B live review 2026-10-09:** full matching576-cell/187-recipe preview
  temporarily staged with verified backups/ledger under
  `generated/phase_b_live_preview`. All190 maps VBSP/VVIS/VRAD and portal
  budgets pass. User approved saved-cell outer/neighbour appearance at logical
  `(22,2)` and the actual corrected Storm Drain west beach/ocean join at
  `(0,0)`. Fresh bounds6/6 and geometry9/9 pass; dense/bridge/snow and matched
  performance remain gates. Lag investigation explicitly stopped by user;
  do not resume it unsolicited or claim a root cause. Jim currently at Storm
  Drain; authorized return target logical22,2/grid22,14, no safe zone.
  Temporary assets must be restored/verified after review; production unchanged.
- **Current-cell edge fires 2026-10-09:** user chose six stable cosmetic fires
  on actual outer-edge buildings, not only neighbouring sky models. Extraction
  now marks rooftop anchors by authored `edges` provenance; core/border roofs
  and wrecks remain separate. Normal-world rendering reuses existing flames
  and smoke at full size under the existing fire toggle, with no damage, sound
  or dynamic lights. GLua186/0, skyline612 assertions/eight recipes and full
  manifest187 recipes pass; old manifest fields are exactly unchanged.
  Only the regenerated preview skyline manifest was staged with GMod closed;
  original backup and ledger hashes verified. Fresh Storm Drain client draws
  six fires from20 edge roofs (24 flame/glow quads,52 smoke quads in capture);
  geometry10/10 and user flame/smoke appearance approval pass. Toggle and
  cross-cell lifecycle checks remain unverified. Phase B remains in progress;
  Jim is still at Storm Drain and temporary restoration remains outstanding.
- Alpha 3.1.0 development is complete: the user
  accepted final Phase H and the milestone on 2026-10-06 after a bounded fresh
  launcher check. [docs/todo-alpha-3.1.0.md](docs/todo-alpha-3.1.0.md) archives
  its evidence and validation limits. Do not reopen accepted phases or infer
  work from historical pending lists.
- Final live checks: renderer 8/8, catalogue/materials 78/78 and
  browser/flight/fog/cleanup 15/15. Human confirmed smooth automatic tour,
  replacement night, soundtrack fade, blackout and return. The captured
  Coastal tour is scoped CPU operation evidence, not a matched/GPU benchmark.
  Final preference/audio/return-state capture was rejected because no connected
  preview admin was available; retain that limit separately from human review.
  User subsequently confirmed Default restored and returned to their survivor.
- Workshop release remains separately deferred: rights/IDs, navmeshes,
  production export/skyline and clean mounts/downloads. Version status is
  `in development` for Alpha 3.1.5, not `released`; no production rebuild/upload
  is authorized. Preview remains the default for approved iteration.

### Archived Alpha 3.1.0 chronology

The notes below record earlier decisions and evidence. Their pending/active
wording is superseded by the final acceptance above, not a current task list.

- The user accepted Alpha 3.0 on 2026-10-04; [docs/todo-alpha-3.0.md](docs/todo-alpha-3.0.md) archives its implementation, regression/live evidence and retained validation limits. Its uncaptured checks are historical limitations, not new Alpha 3.1.0 work.
- Alpha 3.1.0 Phase E is accepted; the user carried remaining sign integration into Phase G. Phase F Wardrobe and revised spiral fabric direction are approved. Filename/fabric catalogue builds; actual client pool regressions pass 5/5 after fixing owned-material pins and failed-build retries. Generated equipment survives reload and independent restoration with exact original inventory cleanup; scoreboard composition moved to PreRender after a verified clipping regression. Cuff-anchored/opposite-limb/front-back calibration, real gore visuals, bloody/walker variants and representative performance remain pending; Phase F is not accepted. Optional client-local sky palettes are Phase H; settle imported provenance and baked-light compatibility before staging/distribution.
- Clothing follow-up: the user subsequently requested hundreds of fabrics, smooth high-detail dye, centred `_chest` artwork and fixes for visible full-back/repeating-back seams. Source now expands to 206 fabrics, supports pink/chest and uses inspected torso-triangle back projection. Physical continuity checks pass 38/38 and rebuilt prototype checks 248/248. Full expanded catalogue staging and fresh human visual review are the immediate gate; do not carry the earlier spiral approval forward as approval of these new outputs.
- Latest clothing direction supersedes combined front/back shirts: user approved enlarged/lowered chest, requested removing combined shirts, raising back prints, colourful untagged backgrounds (explicit light/dark rules unchanged), and raised left/right thigh prints. Published790finishes/792Wardrobe/3178owned files, matching896finish caps and unchanged16target pool. Both thigh placements pass actual topology checks118/118; built catalogue5124/5124, fabrics2754/2754, prototype266/266 and fresh preview static18/18/inventory51/51 pass. Human review of the newest back/thigh/palette outputs remains pending. Do not repeat earlier accepted chest/dye/back-fix questions; review only the newest placement/palette changes.
- Distribution work is authorized within Alpha3.1.0 before further large content expansion. **Both city and preview ship; preview is the player sandbox.** `workshop-settings.json` and `bin/build_workshop_packages.ps1` own allowlisted inventory, report-only exclusions/orphans, byte-budget shards and isolated staging/GMA verification. Never delete reported unowned assets automatically or migrate the installed development tree. Strict release is blocked by missing navmeshes, legacy city export/no city skyline manifest, rights clearance and final Workshop IDs; no production rebuild/publication is authorized by packaging work. Packaged manifests/markers enforce compatibility and deployment gates; loose development remains unchanged. Clean package mounts/downloads and human visual checks remain separate acceptance gates.
- Launcher Content Addons/Recheck/Back UI is user-approved in loose preview. Core owns both launcher BSPs. Settings use safe `pending:<package-id>` labels, never fake numeric Steam IDs; real IDs are assigned by creating private Workshop items, then rebuilding/updating those same items. Builder does not upload. Subscription/download/mount states are distinct and mounted compatibility gates deployment, not subscription alone. Fixtures46/46/live distribution9/9 pass; actual published-ID and clean-mount acceptance still deferred until publication.
- Cuff-up extension is published and user-reviewed on male/female left/right sides:866finishes/868Wardrobe/3482ownedfiles. Separate bottom-aligned `pants_cuff`/`pants_cuff_right` presets preserve all790priorfinish/itemdefinitions and ownedfiles; `_pants_cuff` permits artist opt-in restrictions. Artwork25/25, topology134/134, prototype306/306, published7319/7319, fabrics2754/2754, GLua175/0; fresh live static18/18/distribution9/9/pool5/5. Package audit6659files/7packs remains within shard budgets;387releaseblockers unchanged. Rear-facing limbs, bloody/walker integration and representative animation/gore/performance remain unfinished; cuff review is not Phase F acceptance.
- Rear-limb artist tags and placements now implemented/user-approved for all eight male/female left/right rear thigh/upper-arm combinations. No rear-tagged PNGs currently; default866finishes/896cap unchanged. Parser106/106,topology170/170,prototype370/370,published7335/7335,GLua175/0. Temporary live fixtures removed,inventory/equipment untouched. Next is bloody/walker integration: mountedgroup03inspection48/48 shows2048sheets/differentUVfingerprints, so survivor1024charts are not approved there. Separategroup03report preserves defaultinspection; group02player path failed lookup and is unverified. Preserve existing gore overrides/material copies and unsupported-model appearance. Phase F remains unaccepted.
- Offline Phase F continuation: user chose shared original blood overlays, not duplicateitems/budget expansion. `build_clothing_blood.ps1` stages3sharedlayers/6files (~4MiB); exhaustiveblood32/32, survivor170/170, independentlynamedgroup03charts/fullbodytriangles56/56, catalogue5753/5753, packaging47/47, GLua175/0. Preview-onlyWardrobeBLOODtoggle and clean/bloodypoolkeys implemented; newclientpoolcases/render/gore acceptance **not run: game closed**. Group03diagnostics remain mask-unapproved; existingnativewalkerblood unchanged. Run chart writers serially for isolation checks. Actualaudit6681files/7packs/387releaseblockers; no maps/uploads/inventory changes. Phase F still needs live blood/gore/performance and independently calibrated walker clothing.
- [docs/todo-alpha-2.9.2.md](docs/todo-alpha-2.9.2.md) archives the completed client performance and quality-presets milestone (accepted 2026-10-02); its baseline and validation remain useful for Alpha 3.0 comparisons.
- Current Phase F evidence supersedes the closed-game/group03 next steps above:
  the user approved blood preview, all fifteen independently calibrated group01
  citizens and actual citizen walker/corpse/detached-piece appearance. **Never
  apply catalogue clothing to rebels**; preserve their native mounted blood.
  Engine mesh transfers pass80/80; no per-model catalogue texture duplication.
  The user subsequently chose independent full-catalogue outfits per zombie,
  not a shared outfit per model/cell, and approved96 shared targets (~384MiB
  maximum RGBA storage plus source/material memory). Individual/ticket identities
  preserve outfits through blood refresh and immutable corpse/limb copies.
  Pool-only publication retains866finishes/868Wardrobe, now3642ownedfiles;
  catalogue8035/8035, packaging48/48, GLua175/0. Live Gore16/16, static18/18,
  inventory51/51, clientpool9/9; the enlarged stress test initially froze/flushed
  the renderer, so capacity/citizen tests now run across frames and passed9/9 again.
  Runtime composition uses a2ms soft frame budget; individual cold builds can
  exceed it. Verified15same-model independent outfits and15mixed-model composites.
  One clean warm mixed-crowd run measured60FPS/0.02034ms clothing-hook average;
  cold builds16.807ms mean/21.452ms max and a failed/stale native-control comparison
  remain validation limits. Actualaudit6842files/7packs/387blockers. Owned probes
  removed, quality restored, survivor alive at preview22,0.
- The user subsequently **accepted Phases F and G on 2026-10-05**, explicitly
  confirming existing checks/earlier skybox reviews are sufficient and asking
  to proceed directly to **Phase H**. Do not repeat Phase G regeneration or
  visual checks merely to close historical checklist entries. Uncaptured
  cold/lifecycle/matched-performance and sign integration checks remain
  validation limits, not pending phase gates; no new checks are implied by
  acceptance. Workshop release rights/IDs/navmesh/production export/clean-mount
  blockers remain deferred. Phase H source eligibility and palette/control
  decisions must be settled before changing the optional client sky renderer.
- Phase H's first-selector source choice is approved: mounted game skies plus
  original procedural palettes; uncleared imports remain excluded. Reference
  mounted paths without extracting/copying assets. Palette/control design and
  actual renderer appearance remain separate implementation decisions.
- Phase H prototype now uses `cl_sky_palettes.lua`: saved Default/Natural/
  Cinematic Options, original context gradients and temporary individual
  preview commands. Default remains native; no BSP relighting or server weather
  changes. Natural daytime layering is user-reviewed. Mounted `sky_day03_06c`
  remains a development candidate, referenced in place. Measured texture-edge
  matching corrected side/top mapping; a subsequent tiny seam was fixed with
  half-texel UV insets without changing rotation. User confirmed seam gone
  after fresh reload; live5/5, GLua176/0. Do not repeat accepted F/G checks.
  Phase H still needs context/persistence/reset/launcher/den/capture/weather/
  performance review and final palette membership. Publication stays deferred.
- Phase H UI follow-up supersedes the dropdown/preview-only restriction:
  user chose automatic palettes plus locally saved individual skies. The
  thumbnail browser offers12cards, context warnings and parent-safe Back/X/
  Escape cleanup; mounted sky remains outside automatic palette membership.
  Options has9collapsible sections and a friendly engine-owned audio notice;
  existing controls/precision/presets/server guards retained. Fresh GLua177/0,
  renderer7/7, browser/Options5/5; user confirmed grid/grouped Options, saved
  selection/reopening and restored mouse/camera control look/work correctly.
- Latest Phase H palette UI replaces state dropdowns with four clickable
  preview slots on the left and individual/native thumbnail choices on the
  right. Built-in Edit creates a personal copy; custom Edit retains its ID.
  Draft assignment/cancel never changes the saved choice. Expanded browser and
  revised editor are user-approved: all four slots visible and picker works. The catalogue
  now has82individuals/12built-ins/36imports,432materialfiles/391.48MiB;
  supplied-author permission specifically clears the additional nine sets
  including MR53. Retain original README files in `data_static/sky_licences`
  and common packages. Assets2383/2383, packagefixtures50/50, GLua180/0;
  fresh renderer7/7, UI/inspection9/9 and materials76/76 pass. Deferred parent
  cleanup is fixed; ordinary editor heights show all four slots. New full-cube
  appearance/aerial-render human review remains; no map builds/publication or F/G redo.
- Latest H continuation adds six automatic variants (18built-ins total), using
  all new sets except John Tron at the user's explicit request; keep that sky
  individual/custom only. User approved variants and real aerial preview/return.
  Fresh renderer7/7, browser9/9, catalogue/context78/78, GLua180/0. Isolated
  weather/light boundaries pass; real weather visuals are not thereby accepted.
  Actual selected custom "Test" (`custom_1`/dusk `imported_mr53`) survives preview
  changelevel with six meshes and byte-identical store. Leave user's custom
  selection active. H still needs live weather/context, launcher/den/map-capture
  and representative performance; do not reopen F/G or deferred publication.
- H live continuation: user confirmed rain/Level-view return, normal den
  first-person/Options round trip and launcher Options. Profiler now includes
  PostDraw2DSkyBox; warm Natural draw CPU0.04866ms/frame is scoped operation
  evidence, not native/GPU comparison. User paused to author a **launcher-only**
  preview area in Hammer with point_camera `Preview_skybox`: camera-only
  position/angles, no survivor teleport; replaces launcher upward sweep only,
  not implemented yet. City cells retain their existing sky/current preview;
  do not add areas or rebuild city templates for this request.
  Weather scheduling restored/verified auto1/manual0. Client remains at preview
  launcher; when ready restore/verify Default and slot2 Jim at logical22,0
  (raw22,12), safe-zone none. Do not move them or rebuild maps while paused.
  Options sections default closed and persist each section's open/closed state.
  The preview-launcher-only TOOLS tab is user-approved. Its left column offers
  Wardrobe, Item/Map Atlas, Sky browser and Content Status. Atlases and Content
  Status use the right side of the launcher frame, not a hub window. Tools are
  read-only; Back/Escape always returns to the main menu, and the window tools
  sit below a rule. Live tests pass: Tools4/4 and browser/Options10/10.
  `content/data_static/version.json` is the single version source; update it
  (and the matching `changelog.json` entry, marked `+`/`-`/`?`) whenever a
  milestone, phase or release status changes. Packaging blocks release until
  its status is `released`. Pre-2.6 changelog entries are reconstructed guesses.
  Full H is not accepted: fresh-load archived persistence, automatic weather/
  context, launcher/den/map-capture and visual/performance gates remain.
- Clothing repeat rules (2026-10-06): placed art has no repeat unless
  `_repeating`; `_notrepeating` suppresses it; new `_sleeve_cuff`/`_sleeves`
  hem placement (`sleeve_cuffs.json`). Published698finishes/2994ownedfiles;
  builder prunes unreferenced caches and unowned staged `catalog_*` files. Static
  suites pass. Follow-up: sleeve canvas is now 112x200 (flames climb from the hem);
  new two-piece `sleeve_cuff_both`/`pants_cuff_both`. Published735finishes/
  3142ownedfiles; static suites pass, live pool9/9; human review pending.
- Launcher follow-up (2026-10-06): user confirmed perfect 3D-sky alignment,
  added invisible G-Man support and saved both launcher scenes. Preserve those
  authored edits. Launcher-only sky inspection now takes off from its authored
  island camera into an eased banking flight; shared pose/PVS, obstruction
  checks and render-scoped selected-sky haze are implemented. Main menu/credits,
  city/den sweep, gameplay weather and baked lighting remain unchanged. Static
  GLua183/0 and mocked-engine Lua flight/fog3786assertions pass; game closed,
  so new live browser cases, route clearance/PVS and motion/haze/performance
  review remain pending. No maps rebuilt; Phase H still unaccepted.
- Latest launcher continuation: user approved flight/haze appearance but reports
  lag. Launcher flight now replaces the main RenderScene (no second panel scene)
  and excludes the menu globe. Automatic profiles tour their four existing
  Day/Overcast/Dusk/Night slots over20seconds; individuals retain10seconds,
  saved choice/serverweather unchanged. GLua183/0 and71mocked tour/render tests
  pass; fresh live tour and matched performance remain pending. User closed
  game and authorized both latest authored launcher builds: preview/city
  VBSP/VVIS/VRAD and staged hashes pass. No world-cell maps regenerated; Phase H
  remains unaccepted.
- Sky retirement (2026-10-06): user requested removing Tropospheric night1
  without diagnosis. Published35imports/420materials;81individuals/18builtins.
  Tropospheric1-3/World'sEnd night slots now use night2; other assignments and
  individual/custom-only JohnTron unchanged. Saved selections/custom slots
  migrate to night2 with custom backup; source/old loose files preserved but
  current sky ownership excludes retired materials from packaging. Catalogue
  2319/2319,GLua183/0,packaging53/53,offline migration90assertions pass.
  Fresh live removal/replacement/migration review remains pending.
- When a milestone runs, phases proceed in order and each phase gets focused static/automated checks as changes land; fix failures before advancing and record static and live results separately. A phase is accepted only on the user's confirmation; a successful map compile alone does not establish in-game acceptance.
- [docs/todo-alpha-2.9.1.md](docs/todo-alpha-2.9.1.md) archives the completed compiler-pool, preset, generation-diagnostics, portal-budget, and test-organization milestone.
- `docs/todo-alpha-2.8.6.md` remains as milestone history and source context for the safe-zone contract and Storm Drain work that landed before the current cycle.
- `docs/todo-alpha-2.8.5.md` and `docs/todo-alpha-2.8.md` are historical context only unless explicitly promoted back into the active tracker.
- When the active milestone changes, update this guide and the root tracker together; do not infer current work from historical phase labels. Archive a completed tracker in `docs/` and re-root its relative links.

## Read First

- [docs/readme.md](docs/readme.md) contains the supported build, staging, in-game, and Walker simulator command sequences.
- [docs.md](docs.md) is the generator reference, including profile behavior, authored tile orientation, Hammer checks, and compile diagnostics.
- [docs/gdd.md](docs/gdd.md) describes intended gameplay behavior. Consult it before changing player progression or survival systems.
- [generator-settings.json](generator-settings.json) is the authoritative configuration schema. Do not infer settings or output paths from filenames.
- [docs/two_by_two_tile_templates_plan.md](docs/two_by_two_tile_templates_plan.md) describes multi-tile template work.
- `walker-simulator/` is the portable C++ walker project; it stays isolated from Lua and generated assets, and its behavior and commands are documented in the developer README. `world-viewer/` is the native Alpha 3.4 generated-world viewer. Both CMake projects write their executables (and the walker GMod module) to the repository `bin/` folder.

## Source-First Engine and API Work

- Consult the [Garry's Mod Wiki](https://wiki.facepunch.com/gmod/) for GLua functions, hooks, realms, signatures, return values, prediction, and documented caveats before introducing or changing an unfamiliar API call. Consult the [Valve Developer Community](https://developer.valvesoftware.com/wiki/Main_Page) for Source entities, keyvalues/inputs, materials, Hammer, and compiler behavior. Do not guess API names, flags, entity behavior, or engine limitations.
- When documentation leaves a concrete question unanswered, inspect relevant public [Valve Source SDK 2013 code](https://github.com/ValveSoftware/source-sdk-2013), which includes HL2, HL2:DM, and TF2 game code and tools. It is not the complete engine source or an exact representation of Garry's Mod's engine branch. Use it as evidence with branch/version caveats, not proof of GMod behavior.
- For lighting questions such as what `light_environment` does, distinguish runtime entity behavior from VBSP/VRAD processing and baked BSP lighting; inspect the relevant game/tool implementation where available rather than inferring behavior from an entity name or keyvalue.
- Record the relevant wiki URL or SDK file/revision with a non-obvious finding. If a source is inaccessible, say so; do not claim it was verified. Use known local implementations and a small targeted in-engine probe for remaining GMod-specific uncertainty. Read public sources in place where practical; do not install another SDK, rebuild maps, or copy SDK/Valve assets into this addon merely to answer a reference question.
- Reuse established repository architecture and previously verified findings. Reading the relevant owner before editing is necessary; repeating a project-wide realm audit or prototyping documented standard APIs is not. Feature-specific decisions and uncertain behavior belong at the start of their owning phase, not in a milestone-wide research prerequisite.
- Try publicly available archives before treating an inaccessible live wiki page as a research blocker.


## Runtime Architecture

- Keep Lua realm boundaries explicit: `init.lua` and `sv_*.lua` are server-side, `cl_*.lua` is client-side, and `shared.lua` / `sh_*.lua` run in both realms. Send shared and client files with `AddCSLuaFile`, then `include` files that must execute on the server.
- Preserve the existing Lua style: `//` comments, spaced function calls, four-space indentation in server files, and tabs where an existing shared/client file already uses tabs.
- World data is accessed through `ZM_World`; safe-zone lookup is owned by `ZM_SafeZones`. Use their APIs rather than duplicating coordinate, map-path, or profile resolution logic.
- Server services share small helpers through `ZM_Util` (`gamemode/utils/server.lua`: first human, profile, whole-number checks, console replies, admin gates, command registration). New `zn_test_*` suites use `ZM_TestHarness` (`gamemode/utils/test_harness.lua`). Alias these instead of redefining local copies.
- `cl_atmosphere.lua` is the client facade; `gamemode/atmosphere/cl_core.lua` initializes the environment, weather, puddle, snow, footstep, screen-effect, fog and diagnostic owners before registering callbacks. Preserve the shared snow/puddle deadline, public table identities, emitter ownership and existing render phases. Do not rely on separate `Think` hook ordering. `zombiesim_dev_test_atmosphere_client` runs isolated fixtures and read-only live checks; visual acceptance still requires a fresh client review. See the client atmosphere module reference in [docs/readme.md](docs/readme.md).
- For Lua logic that can run against explicit engine fixtures, reuse `tests/glua/harness.py` and `ZM_TestHarness`; follow the [Shared offline Lua fixture harness](docs/readme.md#shared-offline-lua-fixture-harness) workflow. Add a focused regression alongside behavior changes when applicable. Keep mocks feature-specific and deterministic, reject unsupported calls, and never inherit live globals or use catch-all no-ops. Report offline logic, GLua syntax and actual-engine/visual results separately; LuaJIT fixtures are neither a full GLua interpreter nor proof of engine behavior.
- Work that runs behind the loading screen reports progress through `ZM_Loading` (`gamemode/sh_loading.lua`): `Step`, `Begin`/`Finish` (pending then `ok`/`warn`/`fail`/`info`), and `Reset`. Server calls take a player target; client calls are local. Use it for new load-time work, including future online services, instead of custom loading text.
- `sh_music.lua` must load before `sh_static_data.lua`, which builds its registry during include. Music uses the engine `snd_musicvolume` control; Source effects retain native `volume_sfx`/master scaling. Do not multiply master/SFX volume again on Source audio calls.
- Register network strings on the server before sending. Keep player persistence server-only through the SQL helpers and retain profile scoping.
- The future online-services API is maintained separately in the root `api/`
  Git submodule; see [`api/README.md`](api/README.md) for its current project
  behavior. It is not yet integrated with live gamemode features. Before any
  API integration, inspect that README and its repository instructions, define
  the client/server trust boundary and request contract, and keep secrets out of
  the client and source control. Steam OpenID proves browser account ownership,
  not live GMod presence; the API README requires a separate server credential
  for presence reports. Preserve the API submodule's independent history and
  any pre-existing changes; do not modify or commit API implementation work
  unless the task explicitly includes that repository. The submodule's current
  remote is GitLab (`git@gitlab.com:gcnet-uk/games/zombiesim-api`); verify
  `.gitmodules` rather than assuming a hosting provider.
- Treat raw grid coordinates as diagnostics only. Display and manipulate logical world coordinates through `ZM_World`; for a cross-map change, verify persisted `CellX`/`CellY`, safe-zone id, and resolved map path with `zombiesim_player_status` after the destination loads.
- Before changing a request involving a “map,” identify the intended surface: the world-map window, HUD minimap, satellite/level view, or Garry's Mod level transition. Locate its owning module and input binding; ask a focused question when the request does not distinguish them.
- Before adding client-side GLua or Derma calls, confirm the API signature from a compatible local call site or current Garry's Mod documentation. Validate new client scripts for syntax and exercise prompt first-run, decline/reset, and reopening paths.

## Generator And Asset Boundaries

- **CS 1.6 addon permission, 2026-10-10:** the user reports explicit creator
  permission to extract and bundle all assets from Workshop addon `2657591603`
  (archived revision `1637211535`), including its underlying Valve assets, in
  this non-commercial ZombieSim project. Retain the source credits and record
  this as user-confirmed permission, not independently verified licence text.
  Do not repeat the permission question for this exact integration unless the
  scope changes or contradictory evidence appears. This is not a blanket
  public-domain claim about Archive.org or a licence for unrelated Valve assets.

- Hand-authored tile VMFs live in `tiletemplates`; base maps, launcher VMFs (`celltemplates/launchers`), and standalone safe rooms live in `celltemplates`. Edit these source assets, not generated files in `generated/src*`.
- `content/` is distributable addon content only. Keep compiler logs/reports/intermediate BSPs and other developer outputs under `generated/`; launcher compiler output belongs in `generated/launcher_build`, while required packaged BSPs/materials remain under `content/`.
- Treat generated manifests, plans, VMFs, BSPs, staged profile maps, runtime JSON, and map materials as pipeline outputs. Regenerate them with the matching profile rather than hand-editing them.
- Every generator script must resolve settings through `bin/resolve_world_generation_profile.ps1`. Use `-WorldProfile preview` for normal iteration; it is isolated from the production `city` profile.
- Preserve canonical rotations and carpark endcap rules. `bin/carpark_endcaps.psm1` owns carpark cap selection and yaw; do not duplicate or derive it from lane role. Confirm orientation changes in Hammer.
- Before changing a placement or yaw mapping, inspect the canonical authored orientation and the exact generated `func_instance` that fails. Validate all four cardinal outputs plus any affected exceptional recipe in the developer zoo; never apply a global yaw offset from a single screenshot or recipe.
- For a visual placement report, identify the selected instance and express the intended relationship in logical tile coordinates and cardinal directions. If the screenshot does not establish whether a piece should be edge-adjacent or in-line/in-front, ask one focused clarification before changing placement logic.
- Before diagnosing or validating a generated layout, resolve its exact recipe filename from the current matching plan, rebuild that recipe from current inputs, and confirm the inspected VMF's instance name, source template, origin, and angles. Do not infer freshness or behavior from a similarly named recipe or an older zoo output.
- Do not change a native model's `ModelOffset` to correct Backrooms placement. Correct the generator's block-cell placement.
- Standalone safe-zone maps are complete templates copied unchanged. Edit `celltemplates/safezones`, not their generated copies.
- Before changing a placement, orientation, or UI layout direction, restate the intended relationship in logical coordinates and cardinal directions, including whether it is edge-adjacent, in-line, in-front, left, or right. If the visual evidence leaves that relationship ambiguous, ask one focused clarification before editing.
- Treat generated plans, VMFs, BSPs, navmesh outputs, and runtime exports as potentially stale until the current matching input is resolved and the affected output is regenerated. Validate the exact artifact that was produced, not a similarly named or previously inspected file.

## Focused Validation

Keep standalone GLua test suites in `gamemode/tests/`, with their realm prefixes
(`cl_`, `sv_`, or `sh_`). Update `include` and `AddCSLuaFile` paths when adding or
moving suites; retain dependency load order. Shared test-runner utilities stay
in `gamemode/utils/`; standalone PowerShell regression tests live in
`tests/powershell/`, while generator/build/support scripts stay in `bin/`.
Static-data fixtures remain under `tests/`.

Run PowerShell commands from the repository root. When generator work is
authorized, follow the [preview workflow](docs.md#preview-workflow) with
matching isolated paths and start with the structural check. Never overwrite
retained artifacts merely by copying a dated example.

Normal wide (3x) motorway cells require the matching approved trusted plan and expanded border/outer rings; the old assembly-report workflow is retired. Root settings keep `vmfBuild.outerEdges.enabled` false, so full-world preview batches use an isolated settings copy with it enabled and redirected profile paths. Full terrain infill is three passes: `build_cell_vmfs.ps1 ... -MeasureCompleteTerrainInfill`, `create_terrain_infill_templates.ps1 -PartialGapLayoutDirectory <src> -CompletePatches`, then `build_cell_vmfs.ps1 ... -SizedTerrainInfill -CompleteTerrainInfill`.

- After structural tile changes, run `./bin/check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData`; inspect affected layouts in Hammer, including generated developer zoos when applicable.
- For planner yaw changes, extend and run focused regressions for the reported recipe and previously correct affected cases before broad regeneration. Building frontage changes must pass `./tests/powershell/test_building_frontage.ps1` and `./tests/powershell/test_multi_tile_templates.ps1` before refreshing the preview plan and VMFs.
- Only use `-SkipVBSP` with `-SkipRecipeRefresh` when the source VMFs are unchanged from the portal preflight. Review `generated/build_<profile>/compile-report.json` for failed or incomplete stages.
- Builds are incremental: `build_cell_vmfs.ps1` writes a generated VMF or den copy only when its content changed, and `compile_cell_vmfs.ps1` / `check_vis_budgets.ps1` recompile a map only when its BSP is missing or the VMF or any `func_instance` it references (recursively, via `bin/vmf_source_dependencies.psm1`) is newer than the build output. Before a compile, state which maps a source edit affects. Do not pass `-Force` or `-ForcePortalData` for routine rebuilds; reserve them for compiler/config changes or a deliberate clean build.
- A full VVIS/VRAD build and in-game launch are deliberate final checks. Batch related changes before launching Garry's Mod; reload `zn_preview_start` after preview staging or `zn_city_start` after city staging.
- For iterative Lua live checks, use Garry's Mod's available hot-reload workflow instead of closing and relaunching the game. When a clean map/spawn cycle is needed, `changelevel <current-map>` reloads the same map without closing the client; verify the destination and player state before interpreting the result.
- For `cl_*.lua`, camera, Derma, and map-transition changes, parsing or compilation is only static validation. Do not report behavior as verified until the affected input path has been exercised in a running client; otherwise state that an in-game check remains.
- For visual results (fades, camera motion, outlines, prompts, highlights, placement), ask the human at the running client to look and report before building automated probes. Use the bridge for state evidence such as `zombiesim_player_status`, not as a substitute for eyes.
- After any Lua change, run `./tests/powershell/test_glua_syntax.ps1` for an offline GLua syntax check. It uses the `gluac.exe` bundled with the GLua Enhanced VS Code extension (Garry's Mod's own `lua_shared.dll`), so `//`, `!=`, `&&`, and `continue` parse correctly. Stock `lua`/`luac` cannot parse GLua. This checks syntax only, not GMod APIs or realms.
- For runtime changes, use a two-part validation matrix: run the narrowest static or automated check first, then exercise the affected in-game command, input path, persistence transition, or client flow. Report static success and live success separately, and explicitly state when live verification remains.
- In long implementation sessions, create or refresh a checkpoint after each subsystem boundary and after a failed validation loop. Record the current hypothesis, exact artifact or command under test, result, and next discriminating check before moving to another subsystem.

## Environment Notes

- **Always launch Garry's Mod for the user** (requested 2026-10-12): do not ask
  them to start it. Use
  `Start-Process 'C:\Program Files (x86)\Steam\steam.exe' -ArgumentList '-applaunch','4000','-console','-disableluarefresh','+gamemode','zombiesim','+map','zn_preview_start'`
  and verify `-disableluarefresh` on the actual `gmod.exe` command line.
  Launching without it lets autorefresh watch this development tree, which
  inflates kernel non-paged memory (observed ~5.2 GiB) and causes startup
  stutter; such samples are not valid performance evidence. With
  `-disableluarefresh`, reload changed Lua via `changelevel <current-map>`.

- The repository is already under Garry's Mod. The active compiler profile resolves `vbsp`, `vvis`, and `vrad` from the game's `bin` directory.
- To find or verify a model or material, list the mounted game VPKs with the installed `GarrysMod\bin\vpk.exe l <path-to-_dir.vpk>` (for example `sourceengine\content_hl2_dir.vpk` or `garrysmod\garrysmod_dir.vpk`) and reference the mounted virtual path. Do not search the user's `addons` folder, and do not extract or copy Valve content into the addon.
- The development command bridge source is `content/data_static/consolecommands.txt`; its acknowledgement is deliberately written outside the repository to Garry's Mod `DATA` at `data/zombiesim/consolecommands.result.json`.
- Send bridge requests with `./bin/invoke_dev_bridge.ps1 -Command '<cmd>'[, '<cmd>']` instead of hand-written wait loops. It returns the result JSON (exit 0) and waits for the reloaded map after `changelevel`. Exit 2 means the server heartbeat (`data/zombiesim/consolecommands.heartbeat.json`) is stale: the game is paused in the Escape menu or loading, so ask the player before resending. Exit 3 means Garry's Mod is not running; exit 4 means a ticking server ignored the request.
- For cross-map command automation or `buildcubemaps`, first run a one-command in-engine capability probe and verify its bridge acknowledgement. Confirm permissions and persistence before implementing a sequencer; retain a single-step manual command fallback.
- Never invoke `lua_*` commands (including `lua_refresh`) through the development console bridge; Garry's Mod security restrictions block that route. To reload changed Lua during a preview test, use `changelevel <current-map>` after confirming the active profile and map. Do not try alternate bridge/RCON paths for Lua execution or refresh.
- Starting `zn_preview_start` puts the client in the launcher/character main-menu flow, not in deployed gameplay. Wait for any briefings and the character menu, deploy an existing appearance-complete survivor, then enter the intended den or city cell before running gameplay/live checks. Confirm the loaded map and player state after transitions; do not treat a connected menu player as deployed.
- Scripts use `Set-StrictMode` and `$ErrorActionPreference = 'Stop'`. Retain parameter validation, path construction via `Join-Path`, and profile-driven paths. In Windows PowerShell 5.1, use `System.Diagnostics.Process` for monitored compiler processes because `Start-Process -PassThru` can expose an empty `ExitCode`.