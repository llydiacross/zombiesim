# Alpha 3.3 - Phased Implementation Plan

**Status: ACTIVE IMPLEMENTATION - PHASE A2, 2026-10-28.** The user authorized
implementation and asked for uninterrupted progress until assistance is
needed. Follow phase order and resolve the prefab editor's outstanding design
decisions before coding. This does not authorize world regeneration,
compilation, broad staging, a maintenance batch, production changes or
publication. Get explicit acceptance rather than equating a passing test
with visual or gameplay approval.

## Priority and handoff

1. **Top priority: prefab editor and explorer.** Start here; do not delay it for
   a general refactor, assets rollout, construction, or a full world rebuild.
   Deliver a small working editor-to-world slice before expanding supported
   content types and integration.
2. **Medium priority: zombie behavior and fair attacks.** Investigate the
   reported camera/culling/despawn issue alongside the affected walker path,
   without assuming they share one cause.
3. **Proposed order, not a user-set ranking:** attributes and armour, job UI and
   calling cards, then structure building. These are substantial independent
   requests; ask before reordering or starting an unapproved phase. Shared
   persistence and art decisions are settled in their owning phase.
4. **Fog is the least-priority presentation feature.** Investigate only after
   higher-priority feature phases, and only implement after a bounded visual
   prototype is approved.
5. **World-generation rules are last.** Inventory the authored sources early
   without changing the generator; implement and batch their integration only
   after the user separately authorizes generator work. Fog's low priority
   does not give permission to start generator work early.

Phases below propose a working order for otherwise unranked work, not a claim
that the user already approved every design decision. Optional/refactor work
must not preempt the prefab editor. The original author notes are preserved
verbatim after this plan; if details conflict, ask rather than silently choose.

### Alpha 3.2 and carried work

The [Alpha 3.2 tracker](docs/todo-alpha.3.2.md) is archived, **not released or
fully accepted**. The user accepted motorway live gate/alignment checks and
the current default-off CSM checks; do not redo them without new evidence.
Its full-world outputs, precise skyline replacements/revision hashes,
motorway-cleanup compile/live validation, Cell Health maintenance execution,
and carried Alpha 3.1.5 Phase D/I closure remain deferred. Record their status
and ownership at the end of this plan; do not block prefab work with a full
rebuild or pretend archival completed them. CSM's separate backlog remains
deferred in [its technical tracker](docs/csm-implementation.md).

## Current evidence and boundaries

- The user has authored new buildings, signs and clothing, but authorship is
  not proof that they are staged, packaged or used in the active preview.
  `tiletemplates/buildings` contains `_ra_` building/skyscraper sources and
  `tiletemplates/army` contains the siren. The user confirmed that additional
  scoreboard variants have not yet been authored. The existing background and
  detail images are the defaults under `content/materials/scoreboard/backgrounds`
  and `content/materials/scoreboard/details`; do not invent extra variants.
  Their original bytes and 750x125 dimensions are unchanged. GLua syntax and
  packaging fixtures pass; the relocated artwork has not been live-reviewed.
- `assets/scoreboard/callingcards` exists and was empty when inspected. The
  scoreboard currently draws the background and detail as separate PNG layers.
  The calling-card pipeline below is planned, not implemented or staged.
- `gamemode/sv_loot_spots.lua` identifies map spots by `MapCreationID` and
  runtime spots by an explicit stable `ZM_LootSpotKey`; runtime prefab props
  must integrate with this owner and the existing profile/cell persistence.
  The current activation roll and 320-unit spacing are existing behavior;
  clarify how an explicitly always-lootable prefab interacts with them.
- `gamemode/sv_transitions.lua`, `gamemode/cl_transition_markers.lua` and
  `bin/transition_gates.psm1` own different parts of gate travel, marker
  presentation and compiled placement. `ZM_World` remains the only route
  availability authority. New prefab visuals must not block or redefine it.
- `entities/entities/zn_walker_zombie/init.lua` currently applies damage in the
  same call that starts its gesture. `gamemode/sv_walker_materialization.lua`
  also removes unengaged zombies based on player distance and grace time.
  These are distinct from Source visibility/PVS culling: reproduce each before
  changing either; the report alone does not establish a common cause.
  `gamemode/sv_launcher.lua` and `gamemode/sv_world_capture.lua` already add
  view origins to PVS for their own contexts; these are prior art, not proof
  that adding a gameplay origin fixes the reported disappearance.
- Attribute persistence includes `Snipers` in `gamemode/utils/sql.lua`, player
  network state, static-data validation and character/preview/scoreboard UI.
  A `Rifles` rename therefore requires a migration and coordinated consumers,
  not just a label change. Existing profession bonuses are derived, not stored.
- `ZM_World` exposes cell bounds/profile/logical coordinates, but do not assume
  the installed runtime export already provides authoritative per-tile
  construction eligibility. Prove what is available; if required metadata is
  missing, design a small explicit export or defer construction rather than
  guessing from props or forcing an unapproved world refresh.
- Current fog spans `gamemode/atmosphere/cl_fog.lua` and `gamemode/cl_skybox.lua`,
  including world/3D-skybox and capture/inspection paths. Preserve their
  existing owners and render lifecycle while investigating any seam.
- No quest-named Lua files were found in a focused filename inventory. Verify
  the actual reward owners before assuming a quest integration already exists.
- A `data_static` directory exists at the Garry's Mod root. Its ownership and
  consumers have not been established; audit exact files and destinations
  before proposing changes. Never delete or migrate it on this observation.

## Phase 0 - Readiness for the prefab slice

**Initial investigation, 2026-10-28:** `gm_flatgrass.bsp` is installed and
Garry's Mod is closed. The preview launcher Tools menu is currently read-only.
The existing spawn lifecycle treats `gm_flatgrass` as a non-launcher map:
without a selected survivor it redirects to the launcher, and with one it
loads persistent survivor state and may redirect to that survivor's map.
Editor entry therefore needs an explicit isolated session and a verified
return path, not a bare `changelevel` or survivor teleport. A level change
affects the server's connected players; decide the initial multiplayer guard
before implementing it.

**User decisions:** begin from a preview-launcher admin session only when no
other humans are connected. Save authored prefabs in server `DATA`, with an
explicit export to addon content for shipping. Use a 3D editor with mouse
selection and move/rotate gizmos plus precise numeric controls. The user
approved a first fixture with two validated mounted props, a 640x640 workspace,
configurable translation/rotation snapping, save/reopen and return to the
preview launcher without changing a survivor. Multiplayer editor expansion
is future work; all players must eventually see the same server-selected
prefab in normal gameplay.

GMod's [`file.Write`](https://wiki.facepunch.com/gmod/file.Write) writes under
`DATA`, not addon content, and reports success or failure. Its
[`LocalToWorld`](https://wiki.facepunch.com/gmod/Global.LocalToWorld) applies
an origin and angle to local transforms. `util.IsValidProp` verifies a
physics object, not universal suitability for every model:
[API reference](https://wiki.facepunch.com/gmod/util.IsValidProp). Existing
loot candidates need a stable runtime spot key. Hammer `func_instance`
transforms for custom point entities already need explicit handling in
`bin/build_cell_vmfs.ps1`; do not assume the eventual prefab anchor works
without a focused test. These are readiness findings, not editor or live
acceptance.

- [ ] Re-read this plan, the archived current-status snapshot, relevant
      `AGENTS.md` boundaries and `docs/readme.md`; inventory exact current
      source/staged inputs and preserve unrelated user changes.
- [ ] Map the launcher Tools/editor route, return/deploy flow, map/profile and
      persistence ownership. Establish a safe restoration path before using
      `gm_flatgrass`; do not teleport or alter the saved survivor as an editor
      shortcut. Verify that the installed map is available before promising it.
- [ ] Inspect existing model/material discovery, static tags, prop spawning,
      loot, gate and blockade ownership. Verify uncertain GMod/Hammer entity,
      transform, networking and mounted-asset APIs against local code and the
      relevant Facepunch/Valve references before choosing an implementation.
- [ ] Settle the minimal authoring/save/distribution contract: server versus
      client ownership, editable data location, shipped content versus local
      overrides, who can edit, supported model paths, and how multiplayer
      clients see one server-selected result. Ask the user where behavior is
      not specified. Do not invent a separate editor process or a full
      generalized entity framework as a prerequisite.
- [ ] Agree the first small fixture and its expected orientation, prop types,
      snapping controls and reload behavior. Record static, live and human
      review evidence separately.

## Phase A - Prefab editor and explorer (top priority)

**Goal:** an author can create, save, reopen, browse and place a useful 640 x
640 prefab without Hammer, using the existing tile orientation conventions.

### A1 - Minimal authoring and persistence

**Accepted:** the user accepted this authoring slice after the editor and
explorer reviews, with world-anchor rotations, overlapping spawned prefabs
and scaled gameplay collision remaining A2 checks. Closer editor zoom and
possible additional camera controls remain deferred to A3. This acceptance
does not authorize world regeneration or accept any later phase.

**Source progress, 2026-10-28:** an initial preview-admin session, server-DATA
document/storage contract, 3D editor, configurable gizmo/number controls and
explicit addon export are implemented. The editor uses a 640x640 guide rather
than rejecting prop overhang. Its export is dry-run by default, protects
existing files unless `-Replace` is requested, and includes exported
definitions in Workshop core packaging. Offline contract/storage/session/gizmo
fixtures pass 21 cases, export passes 13 assertions, packaging passes 68,
and GLua syntax passes 295/0. Garry's Mod is running with
`-disableluarefresh`. A read-only slot probe confirmed one preview admin at
`zn_preview_start`; a same-map reload loaded the latest source. The earlier
console-only `zombiesim_player_status` call produced no player report and was
not evidence that no human was connected. A read-only persistence baseline was
captured before reload. `zn_test_prefabs` then timed out without an
acknowledgement or report while the heartbeat continued; a separate read-only
slot probe succeeded afterward. The local console log is stale, so request
the current in-game error before retrying or claiming a test result. The user
reported that `contractTests` was nil in the registration module. Its nested
`include` paths were relative to the test file rather than the gamemode root;
registration now receives dependencies from `gamemode/init.lua`, following
the documented [GMod include path rules](https://wiki.facepunch.com/gmod/Global.include).
The offline registration fixture passes 11/11, and after a fresh same-map
reload `zn_test_prefabs` passes 11/11 in the preview launcher. The approved
fixture models `models/props_c17/oildrum001.mdl` and
`models/props_junk/wood_crate001a.mdl` resolve from the installed
`hl2_misc_dir.vpk`. The pre-editor city/preview persistence baseline hash is
`114b276049cdc9e2053d359b8160c6fc6667d79adf9f5f7432d4f3f70e1223e4`;
compare the same stored sections after returning from the editor. No live
editor, visual review, two-prop fixture or survivor restoration has yet been
verified; none of A1 is accepted on static evidence. City spawning, loot, and
broader prefab types remain A2 work.

**First live attempt:** the user entered `gm_flatgrass`, but the editor did
not open because its fixed vertical trace did not reach the ground. Inspection
of the installed BSP found player spawns around Z -12287 and ground around
Z -12288; the previous trace ended at -8192. The trace now brackets the actual
map spawn height. The editor session also exposed an existing danger-star
polygon initialization error; its vertices are now initialized before
triangles, and gameplay HUD/crosshair drawing is suppressed during the
isolated editor session. Focused offline workspace and HUD regressions and
GLua syntax pass. The player has since returned to `zn_preview_start`/preview,
the session marker is absent, and a fresh persistence report matches the
pre-editor city/preview baseline hash exactly. Reload the current launcher to
load the fixes, then repeat editor entry and verify the real trace, controls
and visual appearance; these source changes are not yet live-verified.

**Live continuation, 2026-10-28:** after a fresh launch, the user cleared an
old owned editor-session marker and opened the editor. The server status
confirmed one owner on `gm_flatgrass`/preview, origin `(3072,3072,-12799.96875)`
and no survivor state loaded. The user reports that the editor, prop
placement, handles and several controls work. Saving initially rejected a
visible valid ID. The client metadata fields updated only on commit; the
editor now updates on typing and synchronizes visible values before save.
Focused fixtures cover both missing callbacks and typing; after an explicitly
approved same-map reload, the user confirmed save/reopen and the `test` prefab
exists in server DATA with one prop. This is scoped live evidence, not complete
two-prop, visual or survivor-restoration acceptance.

The user requested a larger thumbnail-based model browser, ground compass,
selectable authored tile references across many tiles, and possible editor
fog/light toggles. The icon browser and north/east/south/west guide passed
focused fixtures and were live-reviewed by the user: browser functionality and
the compass are accepted for now; fuller UI polish is deferred to Phase A3.
The user prefers an editor-only bright/dark lighting switch; exact rendering
semantics and the requested fog controls remain to be settled.
The user wants selectable reference models for many authored tiles, starting
with a straight road example. A read-only inventory found 227 authored tile
VMFs outside `tiletemplates/dev` and confirmed the installed model compiler.
The existing skybox
mesh extractor omits some geometry and records props separately, so it is not
proof that a tile preview would faithfully represent the source. Inspect the
exact requested assets and validate one isolated 3D reference first; ask before
model compilation or a broad output batch. Do not silently substitute a flat
image.

The user returned to `zn_preview_start`/preview after the save/reopen check.
The session marker was absent and stored city/preview persistence matched
the recorded pre-editor baseline. After reloading for the browser/compass
review the user re-entered the editor; read-only status confirms the owner,
one human and no survivor state loaded. Preserve the user's `test` prefab and
again verify return and stored state after this session. The approved
two-prop round trip and wider A1 acceptance remain open.

**Approved road/atmosphere prototype:** the user approved one isolated
straight-road 3D model and a visually simulated bright/dark editor preview
with representative in-game fog. The source `tile_road.vmf` has a 640x640
footprint, four solids, no props and five mounted materials. An isolated model
was compiled under `generated/prefab_road_reference_20261028`: 46 extracted
triangles, bounds `(-320,-320,0)..(320,320,40)`, model companions present.
The shared extractor omits bottom ground faces; its output is not yet a
general faithful VMF converter. A reversible staging script recorded and
hash-verified 18 previously absent files across `content` and the game root;
its ledger is `generated/prefab_road_reference_20261028/staging-ledger.json`.
No maps or world exports were generated. Road reference selection is
editor-only, not saved as a prefab prop; fog uses the preview world's
`inner_city` profile and dark mode is a labelled screen grade, not physical
lighting. Focused prefab/atmosphere fixtures and compiled/staging tests pass.
After a fresh launcher reload, the user confirmed the road appears correctly
textured and aligned, fog and simulated dark mode work, and selecting No
reference removes the road. These are scoped human observations, not proof of
general tile conversion or release readiness. The current editor session
remains open; verify return and persisted survivor state separately before
expanding the library.

**Two-prop and scaling follow-up:** the user confirmed the two-prop
`test123` prefab saved and reopened with its transforms. A separate read of
the saved JSON confirmed two props, and after return to
`zn_preview_start`/preview the session marker was absent and stored
city/preview data again matched the recorded baseline. The user requested
double-click cycling between Move, Rotate and Scale. They chose uniform scale
first with a practical positive range; independent-axis stretching is
deferred until matching collision can be supported. GMod's
[`Entity:SetModelScale`](https://wiki.facepunch.com/gmod/Entity:SetModelScale)
supports uniform scaling, while
[`Entity:EnableMatrix`](https://wiki.facepunch.com/gmod/Entity:EnableMatrix)
is a client render transform, not by itself a verified collision solution.

Source now implements double-click mode cycling, uniform scale from 0.1 to 10,
0.1 scale snapping when snapping is enabled, numeric editing, and scaled
selection bounds. Existing schema-1 prefabs without `scale` load at 1 without
being rewritten; explicit saves and exports preserve valid scale. Focused
offline document/storage/client fixtures pass, export passes 16 assertions,
and GLua syntax passes 295/0. After reload, `zn_test_prefabs` passes 13/13.
The user confirmed double-click cycling works, but reported that the box
scaled while the prop did not and that the gizmo gave no clear mode cue.
The preview now uses the documented client `RenderMultiply` scale matrix and
matching render bounds; Move draws arrowheads, Rotate selectable rings, and
Scale square-ended handles. Focused client regressions cover the intended
matrix/bounds and handle selection. The user returned to the preview
launcher; the session marker is absent and stored city/preview persistence
matches the recorded baseline. Reload and verify the actual prop and all
three handle styles in game before declaring the fix successful. Scaled
gameplay spawning/collision are not implemented or accepted.

**Scale/rotation live follow-up:** the user confirmed the render-matrix scale
fix visibly scales the prop and the saved size restores. They found ring
rotation unintuitive: vertical movement did little and direction could feel
reversed. The original implementation used horizontal mouse displacement,
not the ring's geometry. Source now intersects the mouse ray with the
selected ring plane and accumulates signed angular movement, including
wraparound; pitch and roll rings follow their relevant prop orientation.
Focused gizmo and client fixtures pass, atmosphere fixtures pass 18/18 and
GLua syntax passes 295/0. This rotation fix needs a fresh-load human review,
including snap on/off and an orbited camera; check the session before reloading.
User confirmation of scale is separate from the pending rotation fix and does
not verify future gameplay collision.

**Ring selection change:** after the double-click lock proved unintuitive,
the user requested a single click to select and highlight a ring, then a
held left-button drag anywhere in the viewport. Releasing a drag keeps the
ring selected; clicking elsewhere without dragging deselects it. Right-click
during a drag cancels that drag. Crossing rings select one deterministically
without rotating on selection. Changing props or documents clears the old
selection, and prop double-click mode cycling is retained. Focused offline
client fixtures pass 24/24 and GLua syntax passes 295/0. The new interaction
requires fresh-load human review, including snap on/off and camera orbit.
Atmosphere fixtures pass 18/18. With the user's save confirmation, the
editor was reloaded on `gm_flatgrass`/preview; a separate status check
confirmed one owner and no loaded survivor state. The user confirmed the
single-click selection, viewport drag/release/deselection, crossings,
snapping on/off, camera orbit, middle-click reset and prop mode cycling work.
After the user returned to `zn_preview_start`/preview, a separate status
check confirmed the editor session closed, the session marker was absent and
no survivor was loaded. The canonical stored city/preview persistence hash
matched the pre-editor baseline.

The user also requested middle-clicking a prop to restore its default
rotation. Source resets its local pitch/yaw/roll to zero while preserving
position and scale; if that prop has a selected ring, the reset also releases
it. Focused fixtures cover the clicked prop, empty space and an active drag;
the user confirmed the reset works in the live interaction review.

**Explorer decisions:** the user chose access from both launcher and editor,
with an interactive 3D preview that does not require opening the editor.
Display names may repeat; the ID remains unique and stable when a prefab is
renamed. The library is shared on the server and any authorized preview
admin may manage it. The explorer remains to be implemented; keep the editor
session's sole-human guard, validate server requests and retain A3 as the
separate later UI-refinement phase.
Source now provides launcher/editor entry, name/ID/description search,
exact-tag filtering, an interactive assembled 3D preview and confirmed rename
and delete through validated DATA storage. Management of the document
currently open in the editor is explicitly rejected until it is closed
there; the New action also releases its server-side open target. Opening a
prefab from the editor explorer retains the unsaved-changes prompt. The user
confirmed the launcher explorer's preview, search, orbit/zoom and close
behavior. They then identified that **Open in Editor** was missing there;
source now validates the selected ID before the map transition, carries it
in the editor session and loads it through the ordinary validated editor
path. Offline explorer fixtures pass 6/6, editor client 24/24, session 10/10,
packaging 68/68 and GLua syntax 297/0. After reload, the user confirmed the
launcher-to-editor transition loads `test123` and the editor explorer opens.
The user also confirmed rename, delete and filtering with a disposable
prefab. After the user returned to `zn_preview_start`/preview, a read-only
status confirmed the editor session closed and no survivor loaded; the
marker was absent and the stored city/preview persistence hash matched the
baseline. Full A1 acceptance remains separate.

**Precision follow-up:** `zn_test_prefabs` now exercises the real engine JSON
serializer through the storage path using in-memory fixture files, including
three-decimal local transforms, scale and four cardinal local yaw values.
After a clean preview-launcher reload, the live suite passes 15/15; the
offline registration fixture uses a mock serializer and is not engine
precision evidence. Actual world-anchor rotations, overlapping spawned
prefabs and scaled gameplay collision require A2 integration.

- [ ] Design a simple explicit prefab record with stable identity, name,
      description, tags and local transforms. Define units, origin, allowed
      bounds/overhang policy, rotation and axis conventions against one known
      640-unit tile; do not infer them from a screenshot.
- [ ] Add a launcher Tools entry and a safe editor session in the agreed
      `gm_flatgrass` flow. Provide a visible 640-unit tile, model selection,
      place/select/move/rotate/delete, grid snap, fixed-increment rotation and
      free rotation. A tile preview such as a straight road is an optional
      alignment aid, not a requirement to rebuild city maps.
- [ ] Save and reload named prefabs without overwriting an unrelated prefab;
      the explorer lists, previews, searches, filters by tags and supports
      explicitly confirmed rename/delete. Decide duplicate-name and ownership
      behavior with the user. Preserve artist-authored source files.
- [ ] Fail visibly in console/UI for invalid or missing prefabs; never select a
      default substitute. Server validates editor permissions, paths, types,
      transforms and models; don't trust a client-supplied path or arbitrary
      entity class. Restore editor camera, controls and saved player state on
      save/cancel/back/disconnect.
- [ ] Exercise round-trip precision, all four cardinal rotations, overlapping
      prefabs, invalid records, permissions and save/reopen/exit. Obtain a live
      user review of placing and editing a simple prop set before expansion.

### A2 - World integration and loot

**Decisions:** normal world spawning reads explicitly exported addon prefabs,
not editable server DATA overrides. An anchor with multiple requested tags
requires every tag. An explicitly guaranteed-lootable prefab prop bypasses
both the activation roll and the 320-unit spacing rule; ordinary loot
behavior is unchanged. No world regeneration, gate-access change or
production staging is authorized by these decisions.
The user chose per-prop stationary/movable behavior. New and legacy props
default to stationary; the editor's movable setting is an authoring contract,
not evidence of world physics or collision support. The user chose to reset
moved props to their authored layout on each cell load, rather than persist
their moved positions.
The authoring contract, selected-prop checkbox, DATA storage and export
validator now preserve per-prop `movable` booleans. Missing legacy values
load as stationary without rewriting the file. Focused offline editor25/25,
storage7/7, contract6/6, explorer6/6 and catalog2/2 pass; export23 assertions
and GLua299/0 pass. After a fresh launcher start, the in-game `zn_test_prefabs`
suite passes 17/17. The user confirmed the two per-prop settings, selection
changes and save/reopen work on a disposable prefab. After return to the
preview launcher and a connected-admin readiness check, the session marker
was absent and stored city/preview persistence matched the baseline.

**First source slice:** a server-side exported-prefab catalog validates
`GAME` files and stable IDs, selects only prefabs matching all requested tags,
and hashes profile/world seed/logical cell/map-anchor identity for repeatable
selection. Missing or invalid exports and unmatched tags return explicit
errors. Offline catalog fixtures pass 2/2; prefab client 24/24, session 10/10,
explorer 6/6 and GLua syntax 299/0 pass. The catalog is not yet wired to
runtime spawning or a Hammer entity; no maps or prefabs were exported.

**Unscaled spawn primitive, 2026-10-29:** `prefabs/sv_spawn.lua` now validates
the complete document and physics-model eligibility before creating native
`prop_physics` entities. It composes local transforms through `LocalToWorld`,
applies each prop's motion setting, allows overlapping placement, rolls back
partial creation failures and attaches cleanup to the anchor. Scale other
than 1 is explicitly rejected until scaled collision passes its own review.
Offline spawn2/2 and the remaining focused prefab fixtures pass; GLua302/0
passes. After a same-launcher reload, `zn_test_prefab_spawn` passes 1/1 in
the actual engine: eight transient props across four cardinal anchor yaws
had the expected transforms and stationary/movable physics flags. The fixture
requests removal of all owned entities before returning. This checks creation
and physics flags, not sustained motion, collision traces or visual appearance.
No real prefab files, survivor data or maps were changed by this fixture.

The spawn primitive is currently used only by the isolated fixture, not a
normal-world service or Hammer entity. The next map-anchor integration must
account for the existing custom-point `func_instance` transform handling in
`bin/build_cell_vmfs.ps1`; raw tile-local markers cannot be treated as
world-space anchors. Generator-source changes and a bounded compiled fixture
need explicit approval under the retained generator/expensive-work gates.

**Approved anchor integration, 2026-10-29:** the user authorized the narrow
generator-source change and one isolated fixture compile, not staging or
entering the fixture. `zn_prefab_anchor` and its FGD definition now expose
all-required tags and an explicit `instance_local` flag for tile instances.
The existing point-entity emitter transforms marked anchors at all four
cardinal yaws and rejects unmarked anchors inside instances. Runtime skips
raw local copies without dropping direct map anchors.
`sv_prefabs.lua` connects exported selection and unscaled spawning after
map initialization and matching survivor/cell readiness, prevents duplicate
spawns across players, and rebuilds authored placement after map cleanup.
`zombiesim_prefab_status` reports owned instances and errors. Runtime prefab
loot and replacement gate content remain unwired.

Validation: runtime owner6/6, spawn2/2, remaining focused prefab fixtures,
packaging68/68 and GLua306/0 pass. The one fixture under
`generated/prefab_anchor_20261029` passes VBSP/VVIS/VRAD with no failed or
incomplete stages, and its visibility budget is 4 clusters/4 portals.
Compiled entity validation passes 27 assertions: four transformed anchors,
four flagged raw copies and one direct anchor. The first two VBSP attempts
returned success despite missing instance files; the corrected relative-path
fixture, not those attempts, supplies the compiled evidence. Visibility also
uses the isolated fixture plan rather than the default plan's unrelated dens.
No installed maps, runtime exports or authored tiles were changed. Actual map-anchor
spawning, visual placement, sustained physics and scaled collision remain
live gates; A2 is not accepted.

**Collision and load-order follow-up, 2026-10-29:** an isolated engine
probe used a mounted oil drum at scales 0.1, 0.5, 1, 2 and 10, with motion
enabled and disabled. On each axis, server `util.TraceLine` collision
extents matched the unscaled control multiplied by the requested scale
within 5% or 0.5 units; the native model scale also matched. Fresh launcher
`zn_test_prefab_spawn` passes 2/2. This tests one model's immediate server
collision, not client traces, sustained motion, gameplay or visible
render/collision agreement. Scaled world spawning remains explicitly blocked.

An early survivor spawn can precede `InitPostEntity`; loot initialization now
waits until prefab creation has run, then resumes even if prefab placement
fails (with an explicit warning). The actual `GM:LoadSelectedCharacter`
branch and deferred owner callback are fixture-covered: offline prefab
runner 12/12, runtime owner 7/7 and GLua306/0 pass. After a launcher reload,
`zn_test_loot_spots` passes 19/19 and `zn_test_prefab_spawn` 2/2; read-only
status reports preview launcher ready, zero anchors and no survivor loaded.
Actual city-cell startup ordering remains unverified.

**Isolated live-anchor review preparation:** the user approved staging and
entering the existing compiled fixture without loading a survivor. The
fixture reuses the owner-only, sole-human editor-session marker rather than
substituting any city map. Its test-only spawn command invokes the same
catalog/anchor spawn owner with synthetic cell ID 0; it does not pretend to
exercise real survivor/city-cell eligibility or loot. The fixture's two
temporary barrels have stationary and movable settings.
Focused session11/11, runtime owner8/8, staging7/7 and GLua306/0 pass. The
stager defaults to read-only inspection, refuses any pre-existing target,
records SHA-256 for each newly staged file, and refuses cleanup if a file
changed. This is permission for the one named BSP and temporary test prefab,
not any other map, world export or authored asset.
The approved fixture is now staged with a hash ledger at
`generated/prefab_anchor_20261029/staging-ledger.json`. A separate bridge
status confirms `zn_dev_prefab_anchor`/preview, one owner/participant and no
loaded survivor. The guarded synthetic-cell command selected
`zz_dev_anchor_fixture` for exactly five compiled anchors and created ten
props; raw instance-local copies were skipped. This is actual compiled-map
and engine creation evidence, but uses synthetic cell ID 0, not the normal
city-survivor path. The user confirmed the isolated fixture's placement,
rotations and unscaled stationary/movable collision by walking into the
props. After owner-only return, separate status confirmed
`zn_preview_start`/preview with no loaded survivor and no editor marker;
stored city/preview persistence matched the baseline. The stager verified
hashes and removed its two temporary BSPs, test prefab and ledger. This is
not proof of actual city-cell eligibility, loot, multiplayer or scaled
collision.

**Scaled isolated review in progress:** a fixture-only native-scale path is
guarded by the sole-owner preview test session; normal world spawning still
rejects non-unit scale. Offline spawn4/4, owner8/8, staging9 assertions and
GLua308/0 pass; fresh `zn_test_prefab_spawn` passes 4/4. The same isolated
BSP and a temporary prefab with 0.5x stationary and 2x movable barrels are
staged with the existing hash ledger. Status confirms the fixture map,
synthetic cell0, one owner, no survivor loaded, five anchors and ten props.
Human visual/collision review is pending. Return through the fixture owner
command, verify the survivor baseline and marker, then restore the exact
ledger-owned files; do not remove them while the fixture is loaded.
The user initially reported the small prop's collision seemed full-size,
then noted a box-shaped hull might explain the appearance. Matched read-only
client/server traces confirmed an actual realm mismatch on the same props:
typical 0.5x horizontal extents were server 7.03 versus client 14.5 units;
typical 2x extents were server about 28 versus client about 14.5 units.
The fixture remains loaded and ledger-owned; no survivor is loaded.
The fixture-only spawner now tries the tiny nonzero scale transition suggested
by the GMod `Entity:SetModelScale` documentation. This is a hypothesis until
the same client/server comparison is repeated; normal scaled spawning stays
blocked.
The nonzero-transition comparison failed: the stationary 0.5x prop now had
approximately 14 units of server collision too, so both realms were wrong.
The fixture reverted to zero transition. The GMod issue
[#6405](https://github.com/Facepunch/garrysmod-issues/issues/6405) suggests a
client `Activate()` call; a tightly scoped fixture-only experiment will test
it, without assuming the wiki's client-physics caveats are resolved.
With zero transition and an explicit fixture-only client `Activate()`, the
same-prop client/server traces agreed within 0.001 units for all ten
samples. The user confirmed walking, standing and pushing felt correct.
Source now experiments with applying that client activation automatically
when the fixture's native prop, replicated scale and transmission state are
ready. Its hooks load only on the isolated fixture; normal world scaling is
still blocked. Offline scale-sync1/1, fixture trace1/1 and GLua313/0 pass.
Fresh automatic-load and transmission-lifecycle validation remain pending.
On a fresh fixture reload, the automatic path required no manual activation:
matching client/server traces agreed within 0.002 units across the ten
sampled props, and the user confirmed walking and pushing felt correct.
After return, the preview launcher had no loaded survivor or editor marker,
stored city/preview persistence matched the baseline, and the staging script
removed the hash-verified temporary BSPs, prefab and ledger. This is a
single-client oil-drum fixture, not evidence for actual PVS leave/re-entry,
multiplayer, other models or deployed city gameplay; scaled normal-world
spawning remains blocked.

**Gate/set-piece readiness:** the current prefab library contains only
editor test documents, not an authored roadblock or transition-gate set
piece. The existing generated transition barricades are car/glass props;
`ZM_World` and the transition trigger still exclusively decide travel
availability. Do not remove or replace those cars, approved motorway
geometry, lane/arrival behavior or gate access without agreeing the first
set-piece content and replacement scope. No generator or map output work
is implied by the isolated fixture approval.
The user chose temporary mounted-prop examples and an isolated review first,
keeping existing gate cars untouched. A source-only fixture now places a
three-drum roadblock across the left north–south road and a two-drum,
open-centre gate placeholder on the right, using the previously approved
straight-road reference. It deliberately has no transition trigger and does
not demonstrate travel or replace approved gate art. Source fixture9/9,
catalog3/3, transition server12/12/client11/11 and GLua313/0 pass. No
set-piece fixture BSP or stage exists yet; compilation remains separately
gated.
The user approved one isolated compile. The set-piece room under
`generated/prefab_setpieces_20261029` now passes VBSP/VVIS/VRAD, 4
clusters/4 portals, and 15 source/BSP assertions for its two anchors, two
road references and absence of transition triggers. The known
`sky_day01_01` texture-size/flags compiler warning remains; the road models
have not yet been visually reviewed in this compiled map. The stager now
supports these two generated test-prefab files without overwriting existing
files; staging/restore fixtures pass 11/11. Nothing was staged or entered
for this set-piece room yet. The user subsequently approved temporary staging
and entry. The room and two test prefab files are now staged under the hash
ledger at `generated/prefab_setpieces_20261029/staging-ledger.json`.
Separate live status confirms `zn_dev_prefab_anchor`/preview, one owner, no
survivor loaded, and exactly two compiled anchors selecting
`zz_dev_roadblock` and `zz_dev_transition_gate`, with five props total.
The user confirmed both road references were textured and both placeholder
arrangements aligned. Owner-only return reached the preview launcher with
no survivor loaded; the marker was absent and the stored city/preview
persistence hash matched the baseline. Hash-ledger cleanup removed both
temporary BSP copies, both temporary prefab files and the ledger. This is
isolated placeholder alignment, not final artwork, gate travel, route access
or motorway acceptance.

**Prefab loot decisions:** the user approved Off, Normal and Guaranteed
per-prop loot modes, with existing props defaulting to Off. Normal keeps the
ordinary activation roll and spacing; Guaranteed bypasses both, as already
agreed. When a Normal prop specifies a loot-group override but its model has
no existing loot rule, the author can set that prop's activation chance.
Source now implements these modes, per-prop group/chance editing, server
group/model-rule validation and export checks. Server-assigned stable prop
IDs survive edits/deletion of neighboring props; legacy IDs derive from
their original index on load and are persisted on explicit save. Runtime
loot keys include anchor ID, length-delimited prefab ID and prop ID.
Guaranteed candidates neither roll nor consume normal spacing slots, and
missing guaranteed spots merge into existing profile/cell rows atomically
without resetting searched items. Failure injection confirms rollback.
The first live selection test exposed a loop-placement error; it was fixed
before further work. A later combined bridge request timed out because the
live suite had a nested include; the dependency is now injected and the
registration fixture covers it. Fresh in-game `zn_test_prefabs`19/19,
`zn_test_loot_spots`23/23 and `zn_test_prefab_spawn`3/3 pass. The latter
uses real engine props with a synthetic anchor for candidate integration,
not a real city cell. Offline editor26/26, session12/12, spawn3/3,
runtime-owner8/8, loot-validation1/1 and runner14/14 pass; export28
assertions and GLua308/0 pass. The user confirmed the Normal and Guaranteed
editor settings, group/chance controls and save/reopen with a disposable
prefab. On return to `zn_preview_start`/preview, the editor marker was absent
and stored city/preview persistence matched the baseline. Actual city-cell
search/persistence remains open.

**Atomic loot-claim follow-up:** the pre-existing persisted-loot acceptance
path gave the item before saving the spot, allowing a duplicate after a spot
write failure. It now reuses the inventory service's transaction and commits
the item and a conditional spot claim together; stale offers, profile
mismatches, inventory-write failures and spot-write failures grant nothing.
Decline failures and invalid/missing spot writes are now reported rather than
returning success, while transient runtime drops retain their separate
behavior. Fresh live `zn_test_loot_spots` passes 30/30,
`zn_test_inventory` 51/51 and `zn_test_prefab_spawn` 3/3 after reload; GLua
308/0 and focused prefab runner14/14 pass. These are isolated/throwaway
fixtures, not a deployed city-cell acceptance.

**City-probe preparation:** the user chose to deploy their existing preview
survivor for a bounded real-city loot check, accepting ordinary gameplay risk.
The new admin-only `zn_test_prefab_city` uses a transient native prefab prop
and a uniquely named throwaway loot profile, exercises the real city
candidate/target/search/decline and persistence path synchronously, grants no
item, moves no player and changes no cheats. It restores the prior active
loot cell, closes its test UI and removes its owned prop and test profile.
A validated DATA recovery marker remains if test-profile cleanup fails;
`zombiesim_prefab_city_probe_recover` removes only the recorded throwaway
profile. Offline probe safety2/2 and GLua315/0 pass. A fresh launcher run
correctly rejected the non-deployed context before creating any marker.
The real city probe has not yet run.
The user deployed their existing preview survivor. Separate read-only status
confirmed map `zz_preview_ed3d3fa48090-cp`, logical cell `(14,0)`, world cell
302 and the matching active preview loot cell. The real-city probe passed
1/1: the actual candidate/target/search/decline path restored the same offer
from its throwaway profile, while the survivor's position and inventory
remained unchanged during the synchronous probe. Separate status afterward
confirmed the original active loot cell was restored and the test marker
was absent. With the user's approval, return to `zn_preview_start` preserved
the saved `(14,0)` location and the stored city/preview persistence hash
matched the pre-deployment baseline. The probe uses a synthetic anchor and
does not validate compiled-anchor city eligibility, an actual accepted
reward, multiplayer or scaled collision. Cleanup verification was then
strengthened in source and passed offline safety2/2; that last verification
change was not reloaded in the city.

**Spotlight decision:** the user chose directional prefab spotlights, with
position, direction, colour, brightness, cone angle and range controls; at
most eight visible per client, with only the nearest one allowed to cast
shadows. The engine's eight shadow-projector limit is shared with other
effects and shadows can reduce frame rate
([GMod API](https://wiki.facepunch.com/gmod/ProjectedTexture:SetEnableShadows)).
First build and review one isolated editor prototype before adding the
networked prefab content type or broad rollout. The existing chest lamp and
accepted CSM experiment retain their owners and behavior.
An editor-only probe now allocates one shadowed, warm spotlight and one
temporary stationary oil drum; it expires after five minutes and cleans up
on stop, owner disconnect or map cleanup. It does not save a prefab light
or alter weather, lighting settings or player data. Offline client probe1/1,
server probe2/2, atmosphere18/18 and GLua320/0 pass. In a fresh editor, the
user could not see the original brightness 1 light in daylight or simulated
darkness. With the same position, direction and colour, brightness 6 made
both light and shadow visible; at brightness 6 with shadows disabled, the
light remained visible and the projected shadow disappeared. The user
approved proceeding to configurable prefab lights. This is a one-light
feasibility check, not a general brightness default or performance test.
Client and server cleanup were separately verified, then the editor returned
to the preview launcher with its marker absent and the stored survivor
persistence hash unchanged. The networked eight-light implementation does
not yet exist.
The user chose the existing 3D move/rotate gizmos plus numeric controls for
lights. A follow-up test used a real editable client-side drum next to the
temporary server drum: the user saw the server drum lit and shadowed, but
neither effect on the editable drum. Preview rendering is therefore an
unresolved integration gate; investigate the editor's manual model drawing
before relying on the prototype for editor appearance.
An isolated engine-drawn opaque client drum was subsequently lit and cast a
shadow. An experimental editor change gave prop models to the engine's opaque
and translucent render groups instead of manually drawing them; the reference
tile remained unchanged. In a fresh editor the user confirmed the drum and
move/rotate/scale controls worked. The first light start still showed neither
effect on the moved editable drum; after restarting the light at the drum's
new position, the user saw both light and shadow and confirmed the shadow
followed movement. This does not isolate render-group changes from projector
refresh timing, or establish all material/lifecycle behavior. Offline
editor28/28, prefab runner20/20 and GLua320/0 pass. Projector and temporary prop cleanup were verified, the session marker was
absent and the survivor baseline matched. A later matched comparison placed
one engine-drawn client drum and one manually drawn client drum before the
same light update; the user saw both illuminated and casting shadows. The
experimental render-group change was therefore removed, preserving the
original editor drawing path. Light refresh timing remains an integration
concern; do not treat the initial mismatch as proof that manual drawing
cannot work. The matched-comparison resources were removed; a separate
launcher check found no editor owner or loaded survivor, the session marker
was absent and the stored survivor baseline still matched.

**Model search pulled forward:** at the user's request the model browser now
optionally searches full paths across mounted model folders, building its
index incrementally while a non-empty query is active. Multiword matching
finds `oildrum` for `oil drum`; local-folder browsing and thumbnail selection
remain available. The user found and added a drum in the running editor.
Offline editor28/28, prefab runner20/20 and GLua320/0 pass. This does not
reopen or complete the broader deferred A3 editor redesign.

- [ ] Implement one authoritative deterministic spawn path that consumes
      prefab-local transforms plus an explicit world/Hammer anchor transform.
      The Hammer entity's origin and rotation are authoritative; verify the
      entity/FGD and map-spawn lifecycle in a bounded fixture before relying
      on a particular engine behavior. Overlap between separate prefabs is
      allowed; don't add geometry-based vetoes.
- [ ] Preserve the authored uniform scale when spawning and verify actual
      render/collision agreement in gameplay before allowing scaled prefabs.
      Keep independent-axis scaling deferred until an approved solution has
      matching, tested collision; a client render matrix alone is not proof.
- [ ] Reuse the current elemental/environment tags where applicable; support
      the requested gate, motorway, radioactive and generic content tags
      without silently falling back when no matching prefab exists. Define
      stable selection from server-owned world seed, logical cell and anchor
      identity. All players on the same server see the same choice; separately
      customized installations may differ. Test repeat loads, multiple anchors,
      reuse of one BSP by different logical cells, and multiplayer consistency.
- [ ] Add lootable/non-lootable settings and validated per-prop loot-group
      overrides through `ZM_LootSpots`, with stable keys across reloads,
      no duplicate grants and profile/cell-scoped searched state. Settle the
      requested guaranteed-lootable versus existing roll/spacing rule explicitly;
      do not change unrelated map loot behavior. Test repeated visits, refresh,
      override, non-lootable, and save failure.
- [ ] Integrate one road blockade and one transition-gate set piece first.
      Retain existing arrows, barricade/access logic, lane positions, arrival
      safety and approved motorway artwork. Test ordinary and motorway gates,
      blocked/available exits and both travel directions in the actual preview.
      Broader traffic patterns follow only after that slice is accepted.
- [ ] Extend the editor/spawner to requested dynamic lights, particles and
      non-trader guard/patrol NPCs in separately testable slices. First settle
      allowed classes, guard behavior, names, animation, clothing ownership,
      cleanup and resource budgets with the user. NPCs are not interactive
      traders; do not promise unverified model/animation support.
- [ ] Verify save/load and deterministic selection offline; then review actual
      editor input, placed props, loot, gate travel and resource cleanup in a
      running client/server. Do not infer a Hammer or live pass from fixtures.

### A3 - Prefab editor UI refinement (user-requested, deferred)

The user accepts the current browser and compass functionally, but the road
selector was difficult to discover below the long left panel. They want a
separate phase to simplify the editor around clearly named workflow areas,
not more ad-hoc controls added to the existing scrolling column.

- [ ] Agree a cohesive, visually pleasing layout with the user before changing
      it. Their starting direction is a **Prefab** button at the top left that
      opens a side panel for prefab actions and settings. Treat this as the
      design direction, not a finished mockup or permission to replace approved
      behavior without review.
- [ ] Map every existing workflow into discoverable areas: prefab list,
      search, metadata, save/delete/export and return; model browsing and
      placement; tile-reference selection; scene/fog/lighting controls; and the
      selected-prop inspector. Propose clear labels, grouping and visible
      active states. Keep the viewport, compass and primary actions easy to
      reach rather than hiding new features below an unrelated long scroll.
- [ ] Define how panels open, close, switch and resize, including whether
      multiple areas can stay open, keyboard/mouse focus, escape, modal
      dialogs, unsaved edits and return to the launcher. Avoid covering or
      intercepting the 3D workspace unexpectedly. Preserve the existing
      right-side inspector's working behavior; the user says it is mostly
      fine, while creator-oriented tools and quality-of-life additions need
      their own agreed scope.
- [ ] Revisit the larger model browser's hierarchy, thumbnails, search,
      navigation, selection and placement flow. It works and is accepted for
      now; redesign presentation in this separate phase, not during the
      current functional slice. Keep direct model-path entry and server-side
      validation.
- [ ] Replace the loot-group ID text box with a discoverable list of the
      game's available loot groups when configuring a lootable prop. Retain
      server-side group validation and the existing model-default/no-override
      option; agree the list's presentation as part of the A3 UI work.
- [ ] Increase how far the editor camera can zoom in. Consider additional
      camera controls with the user as part of this UI phase; agree their
      behavior and verify close-up navigation, input ownership and cleanup
      before implementation. This request is deferred, not a change to the
      current editor interaction slice.
- [ ] Produce a bounded mockup or first implementation for human review,
      then exercise every panel/close path, saved and unsaved prefab flows,
      selection, gizmos, numeric edits, reference/fog/lighting state and
      return to the launcher. Test at different resolutions and document
      resource/performance limits separately from visual acceptance.

## Phase B - Zombie behavior and culling (medium priority)

- [ ] Capture a matched preview baseline: profile, map/logical cell, camera,
      nav availability, population, visibility, zombie lifecycle reason and
      player position. Reproduce object disappearance separately from walker
      removal. Distinguish engine PVS/render culling, camera visibility and
      server relevance/cap/transition cleanup before selecting the owner-level
      fix. Do not change visibility or spawn caps as an unmeasured blanket fix.
- [ ] Design bounded, server-authoritative idle/wander, slow movement,
      directional sight plus line-of-sight, hearing, limited alert propagation,
      and memory/territory behavior. Specify what persists across a cell load
      and how nav failure is handled. Grouping and zombie infighting are
      exploratory; ask before adopting them as mandatory behavior.
- [ ] Separate attack wind-up, one damage event and recovery. Confirm actual
      model animation timing in GMod; revalidate target, range, line of sight,
      alive/state at impact so dodging works. Cancel on death/removal/transition
      and prevent repeated damage from one swing. Add requested groan,
      footstep and attack cues without introducing unbounded sound spam.
- [ ] Agree actual damage and armour interactions with the user; preserve
      existing headshot, boss, gore, XP, corpse, loot and Walker ticket
      contracts. Coordinate final balance with Phase C rather than silently
      changing all combat. Keep the C++ worker and GLua snapshot ownership
      separate; only change the simulator if the intended feature needs it.
- [ ] Add deterministic target/cone/hearing/alert/timeout and hit/miss/cancel
      fixtures, then live-test movement, stealth, fair dodge, no-armour and
      armour controls in the actual city with matched player/camera settings.
      Preserve player state; do not rely on cheats or AFK/notarget settings.

## Phase C - Attributes and armour

- [ ] Inventory definitions, weapons, professions, UI, SQL migrations and
      saved profiles/character slots before specifying new `Pistols` and
      `Explosives` and renaming `Snipers` to `Rifles`. Decide whether and how
      existing sniper points transfer; preserve points and avoid double
      allocation. Ensure migration is atomic, repeatable and rollback-safe.
- [ ] Classify existing armour as light/medium/heavy and define equipment/job
      requirements and proficiency with the user. Agree concrete resistance,
      movement, stamina regeneration and skill effects; the requested light
      skill reducing heavier-armour penalties must not be silently inverted.
      Optional special bonuses require a separate design decision.
- [ ] Apply modifiers once through the existing authoritative player/movement,
      inventory and damage owners, including equip, unequip, death, spawn,
      implant refresh and reload. Never compound speed modifiers. Keep current
      survivor inventories and unarmoured behavior valid.
- [ ] Test fresh and legacy profiles, every class and job, persistence,
      migration retries/failure, stamina/movement boundaries, damage and
      actual in-game weapon/armour use. Update GDD and focused fixtures.

## Phase D - Jobs and calling cards

- [ ] Prototype the profession grid, selected job icon and detailed attribute
      table in the existing creation flow, with clear placeholder backstory.
      Preserve point allocation, server validation, existing character data,
      Back/cancel and mouse ownership. User reviews the UI in a running client.

### D1 - Calling-card artist pipeline and catalogue

**Goal:** artists can drop in finished PNGs or configure generated cards,
then build and stage both types through one catalogue. This is part of the
calling-card phase, not a reason to interrupt the top-priority prefab work.

- [ ] Use the existing `assets/scoreboard/callingcards` as the artist-source
      area. Define a simple editable JSON recipe file there, inspired by the
      sign and clothing workflows, plus a separate generated runtime catalogue.
      Keep artist inputs, temporary build outputs and distributable content
      distinct; choose exact filenames and commands when this phase begins.
- [ ] Discover standalone finished PNGs without requiring a JSON entry for
      each one. The requested examples `custom_background.png` and
      `custom_details.png` must import as finished background and detail
      cards respectively and be staged in their corresponding scoreboard
      directories. Preserve the artist's original image and transparency;
      never silently replace it with a generated variant. Resolve the naming
      rules for other PNGs and ambiguous categories before implementation;
      report unclassifiable or conflicting files explicitly.
- [ ] Let JSON recipes reference images in the same source area and configure
      generated background or detail variants. Support at least repeating
      emblems and full-cover image/pattern layers, with artist-controlled
      composition, colours and output choices. Distinguish recipe ingredients
      from standalone finished cards without forcing artists to register every
      finished PNG; a clearly classified finished card may also be used as an
      ingredient. Settle the minimal schema, layering and naming rules with
      the user rather than guessing an elaborate procedural design.
- [ ] Produce reproducible, stable card IDs, names, layer categories and
      output paths. The runtime JSON catalogue identifies handcrafted and
      generated cards and their materials; adding or reordering unrelated
      sources must not silently change existing IDs or owned selections.
      Duplicate IDs, unsafe paths, missing source images, malformed recipes
      and output collisions must fail visibly. Decide names, metadata and
      migration behavior for renamed/removed designs before implementation.
- [ ] Preserve the existing `backgrounds/default.png` and
      `details/default.png` as built-in defaults. Do not overwrite or prune
      manually authored/unowned files. Produce a small, reviewable preview
      first, report planned variant counts and output paths, and agree any
      generation budget with the user rather than silently dropping variants.
      Check supplied artwork rights; do not extract or copy mounted Valve
      content into the addon.
- [ ] Stage validated finished and generated PNGs to the corresponding
      `content/materials/scoreboard` paths and any required development-game
      destination, with verified copies. Put the generated catalogue in the
      gamemode's `content/data_static`, not the deferred root `data_static`
      directory. Wire its static-data loading and Workshop ownership: the
      scoreboard material directory is already recursively included, while
      a new catalogue must be added to the explicit core-data allowlist.
      Preserve the previous working catalogue on a failed build or stage.
- [ ] Add focused fixtures for direct PNG discovery, both example suffixes,
      referenced emblem/full-cover images, transparency, deterministic
      generation, stable IDs, defaults, malformed/missing inputs, collisions,
      preservation of unowned art, staging and packaged catalogue/material
      coverage. Validate the existing scoreboard aspect and actual rendered
      result with one handcrafted and one generated example before broad
      rollout. Static tests alone do not accept their appearance.
- [ ] Document the artist workflow, supported filename conventions, recipe
      settings, dry-run/build/staging steps, ownership and recovery behavior.
      Ask before an expensive catalogue build or broad staging; this planning
      request does not itself run either.

### D2 - Calling-card ownership and scoreboard

- [ ] Consume the catalogue for both handcrafted and generated cards.
      Clarify names, default ownership and the account versus character/profile
      ownership scope before designing persistence. Owning a card unlocks its
      use; it is **not** a backpack item or inventory slot. Settle how a player
      chooses among multiple owned layers and whether selections are shared on
      the scoreboard. Preserve existing default presentation for old saves.
- [ ] Provide server-authoritative ownership/reward and credit-purchase paths,
      atomic with existing trader/credit transactions; duplicate/replayed
      requests must not charge twice. Integrate with an existing quest owner
      only if present; otherwise define a reward API and explicitly defer
      quest-specific wiring until that system exists. No loot drops.
- [ ] Implement the scoreboard pencil, owned/locked choices and display
      replication with safe defaults for existing survivors, plus purchase,
      reward, profile isolation, reconnect and UI-close tests. Review actual
      materials and presentation; do not fabricate missing artwork.

### D3 - Credits music and camera-facing dancer heads

- [ ] Integrate the supplied `content/sounds/music/credits.mp3` with the
      existing launcher music owner when credits open. Respect the engine's
      `snd_musicvolume` control, stop/fade cleanly on every credits close or
      map transition, and restore the existing launcher soundtrack without
      overlapping channels. Validate the source and its distribution rights;
      include it in the packaged sound path without assuming the existing
      city/den music registry already owns it.
- [ ] Make each of the four credits dancers turn its head toward the **current
      credits camera** while preserving the approved poses, body motion, facial
      expressions and camera choreography. Investigate ragdoll bone/physics
      behavior for the actual four models first; use a bounded custom
      client-side solution if needed, not a Hammer-only assumption or a
      networked per-frame pose. `Entity:SetEyeTarget` changes eye gaze, not
      head orientation, and uses ragdoll-local coordinates.
- [ ] Resolve actual bone axes, missing bones and camera lifecycle per model;
      clamp and smooth finite rotations, restore original state on all exits,
      and avoid affecting other ragdolls or survivor gameplay. If a model or
      engine path cannot support the effect, report it explicitly rather than
      silently claiming all heads track.
- [ ] Test credits start, natural end, Escape/click, re-entry and launcher
      return, both launcher profiles, audio volume and cleanup. Obtain a live
      human review that the supplied song plays and all four heads actually
      follow the moving view without disrupting the approved presentation.
      Keep this addition behind the current prefab priority.

## Phase E - Player structures and claims

**Design gate:** settle claim ownership scope, overlap/collision and shared
permissions, construction materials/recipes, recovery of existing contents on
expiry/reclaim/destruction, damage rules, door/key access, and how airtightness
and front doors are identified. Do not choose these silently or conflate a
wireframe preview with a completed structure.

- [ ] Establish authoritative eligibility for a 640-unit **core** tile:
      terrain/detail only, never road, border or a tile containing another
      building/object/claim. Check all sides, occupied multi-tile buildings and
      shared BSPs; if runtime metadata is inadequate, present the minimal
      data requirement rather than generating the world without permission.
- [ ] Design claim token purchase and atomic consumption/claim creation.
      Scope state by world profile, logical cell and tile, not BSP name alone.
      Support adjacent expansion only with another token. Persist a 30-day
      last-visit expiry across restarts; settle server clock/visit semantics.
      Expired structures may be salvaged by others; a new token replaces the
      prior claim and starts a fresh period. Define safe content handling
      before reclaiming and test races/replays/failures.
- [ ] In construction mode show the claimed-tile boundary and keep placement
      within owned tiles. Implement the requested mutual zombie/player
      non-interaction only while the player is eligible and nearby; exiting
      the mode or going far away ends protection. Agree the distance and test
      death, disconnect, multiple players and transitions.
- [ ] Prototype modular 64-unit foundations and snap points, 32-unit halves,
      16-unit-thick walls and triangles, with wall/floor/roof/door/window
      pieces. Use properly referenced mounted wood/stone/metal/concrete
      textures; verify asset/tool availability and rights, never copy Valve
      content. A configurable material-group source is a design option, not
      permission to generate an entire catalogue before a small visual review.
- [ ] Server validates the wireframe placement, ownership and snap relationship.
      E contributes wood/materials atomically; insufficient materials, repeated
      input and interrupted sessions cannot duplicate pieces or items. Once
      complete, fade to the real structure. Persist geometry, per-material
      health, repair/damage and destruction across map reloads.
- [ ] Add storage boxes with separate persistent inventories and **no
      user-facing item-count cap**, with secure access and safe transaction/
      paging behavior. Doors fit frames, lock and support agreed keys or
      permissions; windows support barricades and curtains. Workbenches and
      other interactive furniture are explicitly out of scope.
- [ ] Define and test airtightness under missing/destroyed pieces and open
      doors/windows; muffle sound/light only for eligible enclosed occupants.
      Without curtains zombies try the front door; after repeated inaccessible
      door attempts they collectively try a wall. Coordinate this with Phase B
      perception/pathing and avoid global scans or infinite retry loops. Obtain
      human review of construction, damage, storage and multiplayer access.

## Phase F - Asset staging and targeted refactors

- [ ] Audit the user's new sign artwork/evacuation data and clothing sources,
      existing ownership/rights and builder inputs. Prepare a bounded sign and
      clothing build/staging proposal, costs and hash/ownership verification.
      Ask before expensive processing; do not overwrite edited sources or
      imply the new assets are staged until verified in the game and package.
- [ ] Inventory `cl_skybox.lua` public table identities, hook ordering, render
      phases and state cleanup before splitting it into focused modules like
      atmosphere. First capture a baseline, then preserve behavior and run
      the relevant skybox/atmosphere fixtures and fresh visual review.
- [ ] Inventory finite-number/vector/angle helpers by realm and semantics;
      centralize only compatible duplicates with load order and NaN guards
      retained. Similarly compare JSON readers' error and search-path behavior
      before sharing code. Do not replace different error contracts with a
      silent default or launch a project-wide refactor for its own sake.
- [ ] Map all materializer/materialization identifiers, commands, docs,
      persisted/config and external/native consumers before renaming to
      spawner/spawning. Define migration or explicit aliases only where
      required; do not break Walker tickets, diagnostics or existing settings.
- [ ] Audit the exact root `garrysmod/data_static` files, their hashes,
      provenance, read paths, current addon/package destinations and other
      owners. Report a precise migration/cleanup proposal; do not remove or
      overwrite shared files without user approval and verified restoration.

## Phase G - Better fog (least-priority presentation work)

- [ ] Reproduce skybox mismatch and double-fog seam on the exact preview map,
      weather, camera and settings, comparing world/skybox fog ownership and
      a known-good baseline. Check sky inspection, map capture and weather
      restoration separately. Consult engine documentation before relying on
      any unfamiliar fog or rendering behavior.
- [ ] Test the simplest existing Source fog adjustment first. If insufficient,
      propose one bounded, isolated fake depth/height-layer prototype that
      keeps distant skyscraper tops visible; do not assume real volumetrics or
      modify approved materials/lighting without evidence and agreement.
- [ ] Compare seam, appearance and matched performance with fog isolated;
      obtain the user's visual approval before rollout. Preserve native/default,
      capture and CSM behavior and document technical limits.

## Phase H - World-generation rules and separately approved output batch (last)

- [ ] Inventory actual renamed/new source files, exact `_ra_`/military tags,
      environments and fixed landmark/army-base rules. Preserve user VMF/VMX
      edits and army-only siren intent. Check all relevant selection paths,
      including skyscrapers, multi-tile buildings, variants and fixed landmarks.
- [ ] Implement the user's rule: radioactive cells select only radioactive
      buildings/skyscrapers, falling back to appropriate terrain/detail when
      none are available; army-base cells use their matching military assets.
      Other environments may use untagged buildings, with matching tagged
      assets preferred when available. Resolve overlapping radioactive/army
      tags, the precise army-base identifier, fallback weighting and landmark
      exceptions with the user before coding.
- [ ] Add focused selection/control fixtures for radiation with/without
      candidates, military, other tagged and untagged environments, renamed
      decorations, siren placement, density tiers, all building sizes and
      protected neighboring cases. Keep accepted roads and motorway placements.
- [ ] Present a single costed preview-output proposal before any plan/VMF
      refresh, compilation, full materials, skyline, navmesh/photo or staging.
      Include matching runtime maps/materials/models, two temporary skyline
      aliases, revision hashes, package coverage, capture compatibility,
      restoration and human review. Keep production city/publication gated.

## Phase I - Deferred closure and acceptance

- [ ] Review the archived Alpha 3.2 Phase F/I/J/K/L and carried 3.1.5 Phase D/I
      deliverables against current evidence. Keep unperformed maintenance,
      photo/navmesh, Satellite/wireframe, skyline/revision and integration work
      explicitly open; agree whether and when to batch it with Phase H.
- [ ] Cell Health batches remain user-started, with options unchecked by
      default. `buildcubemaps` is a manual native-console action; a persisted
      Yes is user confirmation, never engine verification. Reuse the existing
      capture queue, importer and watcher; test restoration before acceptance.
- [ ] Record focused automation, compiled/artifact checks, live paths, human
      review and retained limits separately for each phase. Do not release,
      stage production or mark either milestone fully accepted merely because
      the tracker was archived or tests passed.

## Decisions to resolve in their phase

- Prefab distribution and editor permissions; server-wide custom content and
  stable seed/anchor identity; exact always-lootable versus spacing behavior;
  supported prop/light/particle/NPC classes and Hammer integration.
- Structure claim scope, 30-day visit semantics, construction immunity
  distance, reclaim/destruction of stored items, keys/permissions, material
  costs, airtightness, curtains and AI path/attack behavior.
- Attribute migration and balance; calling-card ownership scope, default
  selections, direct-PNG naming/category rules, recipe schema and generation
  budget, supplied artwork rights and quest availability.
- Radiation/army overlap and fixed-landmark exceptions; fog acceptance criteria
  and whether any measured baseline warrants a more expensive approach.

## Original author notes (preserved)

# Alpha 3.3

These are the things I have already done

# Additions

- Added new skyscraper buildings for radiatioactive zones, various new buildings added. Improvements to the current buildings
- Added new textures for billboard signs along with new data for evacuation signs, stage new billboard/signs
- Added new clothing textures, stage new clothing

# Changes

- Some of the buildings have been renamed to better reflect their density and purpose as well as that a bunch of edits have been made to improve their appearance and functionality.
- Some decorations have been renamed and are now industrial tiles in the buildings folder, such as the dumps.
- the army folder (which is used for military-themed decorations and buildings) now contains the siren and should be only placed now in the army base

This is what the plan is for the upcoming updates and changes.

# Upcoming Updates and Changes

 
## Better Fog (least priority)

- Figure out a way to improve fog.
 - Fog right now kind of just masks the skybox and makes it look opaque and is genuinelly not that convincing. I think this is due to how source does its fog implementation. I would like the fog to possibly instead be volumetric, possibly faked in the skybox so instead of a kind of an overcasting fog there is just kind of a dim layer of fog and then you can see the skyscrapers pop out of the fog layer from a distance. 
 - Think of the simplest way to achieve this effect and consider if it could be achived already with current source fog implementation
 - Sometimes, Fog doesn't always align with the skybox model, leading to visual inconsistencies that need to be addressed.
 - Furthermore, what can happen is kind of a "double fog seam efffect" when traversing through the cell and you are looking at the skybox, kind of breaking the illusion of fog as it appears there are two fogs overlapping each other.

 ## Prefab Editor System (top priority)

- I would like to create a system which will allow me to position props and other elements to create prefabs that can then be reused. The idea is that this system which i am envisioning will probably be accessible via the main menu, loads you into gm_flatgrass where you enter an editor that gives you a 640 grid tile to place down props onto. Using this I will make the blockcade configurations that you place on the roads. Also we can use this system to create transition gates that replace your current system of just placing a car, with a re-defined set piece dependent on the environment
- This system would allow you to position the props, save them as a name, and them some how that prefab can then be used by the system in areas such as the transition gate and in blockades. This feature would also allow us to create car patterns for the motorway so that traffic can be more dynamically generated and varied, enhancing the overall realism and immersion of the environment and I don't have to place it all down in hammer. Since the editor is making the user place the props on a 640 by 640 tile it should be easy to place this down into our own with out any issues other than figuring out the rotation but we will use the same oritentation rules as twe do for the tiles
- This system would allow the user to place props which are lootable, and non lootable, and possibly even override the loot group for specific props, giving more control over the distribution and availability of loot within the game environment. Maybe you can make this prefab for instance always output a lootable prop?
- You should be able to move the props around, rotate them, and adjust their properties within the prefab editor to achieve the desired layout and appearance.
- It should contain basic settings such as the prefab's name, description, and any relevant metadata that helps identify and categorize the prefab within the editor. Also options to snap props to the grid for precise placement. Or rotate them at fixed increments for better alignment. Or rotate them freely. 
- The Prefab Editor System should be really two parts, one is the editor its self, the other is the explorer to see and manage the existing prefabs, allowing users to browse, search, and organize their prefabs efficiently.
- Various tags could be transitionGate (used to replace the "red car" prop we place down now)
 - transitionGate Motorway (special transition gates for motorway)
 - Radioactive (for radiative zones)
 - Take advantage of the current elemental tag system
- When requesting prefabs, you could for instance in hammer use a "Generic" tag to filter and find prefabs that match the desired category.
- If a prefab fails to load, simply error in console and do not fall back to a default prefab.
- Generic tags might include
  - bodys (for piles of bodies or corpses)
  - ammoCache (for caches of ammunition)
  - medicalCache (for caches of medical supplies)
  - weaponCache (for caches of weapons)
  - ambulance
  - policeCar
  - fireTruck
  - roadDetail (for details and props related to roads)
- Take authority of the positioning and rotation from the hammer entity in hammer of the preset if spawned in hammer
- Prefabs some how are "tagged" for their use, so for instance if you make a road blockade, or a transition gate, it is tagged that way and then used by the system to automatically place the appropriate prefabs in the correct context within the game environment.
  - Note: This does mean that determanistically each player might not have the same preset if they were to customize their game. This is okay, as everyone should have the same when we launch anyway, and modding through this system is okay.
- Maybe you could even include the ability to load a preview of a tile for instance the road straight so you can align your prefabs accurately with the existing environment.
- Eventually, this system will take dominance over just placing prop dynamic and stuff in hammer, and we will develop a hammer entity that we can use to reference these prefabs and spawn them into the world where we want in hammer. For instance, I can edit the motorway pieces so they include this prefab spawning entity for the purpose of crashed cars and other things like that
- Obviously, well have no way to preview what kind of entitys will be spawned around the point of origin set in hammer, so the artist will have to know beforehand what the prefab contains and plan accordingly.
- Prefabs can overlap over prefabs. They are simply just a group of props that are grouped together and spawned in at the same time. Editable within the prefab editor, allowing for adjustments and refinements before being used in the game environment.
- Prefabs could be rigged to be randomly decided when you join a cell. This would allow motorway car patterns to change per cell. It would need to be the same for all players so it would be determinstic based on a shared seed or some other consistent factor.
- Prefabs could also take advantage of garrysmod features and include things such as dynamic lights, particle effects, and maybe even you can place down NPC's. 
- Note: On NPCS right now we don't have NPCS who are not traders, these NPCS are different from traders as they are considered "guards" or "patrols" that protect certain areas or follow specific behaviors within the game environment so they act more like the half life 2 rebel AI and just shoot any zombies that come close to them as needed. They have names above their heads and you cannot talk to them directly.
- The NPCS would just stand there and you can set the animation and also the clothing they are wearing, referencing with our clothing system already
- Through the prefab system, we will be able to also create detail to be placed into the world, like piles of bodies, broken down albumances, abandoned vehicles, and other environmental storytelling elements that enhance the immersion and realism of the game environment.
- This will allow for a more dynamic and visually rich environment, where the world feels lived-in and responsive to the player's actions and the ongoing narrative.

## Calling Cards

in the materials folder under the scoreboard folder currently there is just two info_header texture for the background and detail. I would to expand this so you the player can choose both of these things. So I want to add more variants of background, and detail.
- See new scoreboard/backgrounds and scoreboard/details folders for all the new variants
- Each variant gets a name and is an item in game.
- You can't find the calling cards, they are given as rewards from quests, or you can buy them from the shop keeper for credits
- Players can equip a calling card to display it on their profile or in specific areas of the game interface.
- Right now, for the scoreboard, we should add a pencil somewhere where you can change your "calling card"
- You don't "equip" the calling card, simply just owning it will allow you to display it on your profile or in specific areas of the game interface. Also, the calling card isn't a item in your inventory either. I was thinking that it doesn't take up an inventory slot for the user and is simply in a seperate special storage just for the calling cards. This special storage box for calling cards is where all calling cards automatically go. That is how we propegate the edit button in the scoreboard to show what you do and don't own.

## Structure building system

- Create a set of tiles to be used for constructing various structures within the game environment.
- Ensure that these tiles are modular and can be easily combined to form different types of buildings.
- Consider including both interior and exterior tiles to allow for complete building construction.
- Implement a system for snapping tiles together to maintain alignment and consistency in the game world.
- Tiles should be based on the tile of a cell, which is 640 units in size. So if we divide that by 10, the base foundation size should be 64 units, and everything else for our structure system should be based off of that, so a half tile would be 32 units. A wall would be 16 units in thickness as it is 64 / 4. 
- We can generate a variety of complex pieces which the player can use to construct unique and diverse buildings within the game environment. We should also include triangle-shaped pieces to allow for more architectural variety and creativity.
- The textures we should use are wood, stone, metal, and concrete to provide a variety of visual styles for the structures.
- The theming and general art style is post apocalyptic, reflecting a world that has undergone significant devastation and is now in a state of decay and ruin. So the structures should look like shantys, makeshift shelters, and remnants of once-functional buildings, emphasizing the harsh and deteriorated environment.
- Take textures from source which are already pre existing and create the models using these textures and create a set of modular building pieces for each texture group.
- Maybe we can define the texture groups in a json file so they are editable, incase we want to generate a new stucture piece in the future. Such as Marble, Granite, or other material types.
- How the building will work is, you will place down a foundation piece, and then using a system similar to rust, using snapping points on the foundation and other building pieces, you can attach walls, floors, roofs, and other structural elements to construct your building. This system ensures that all pieces align correctly and maintain structural integrity within the game world.
- I would like it so first you place down the basically a wireframe version of the foundation or piece you would like to build, then by pressing E you can "add wood to it" and then once it has enough wood, it fades from wireframe into the structure. 
- Structure pieces have a health dependent on the materials used and can be damaged or destroyed by player actions or environmental factors. This adds an element of strategy and realism to the building system, as players must consider the durability of their structures and maintain them over time.

- In order to place down a structure, there is a few conditions which must be met:
- One: The (tile) or part of the cell you are currently in is an empy cell that is not occupied by any other structure or object. This means there is no building there and it is just a detail tile or a terrain tile. It cannot be a road tile, or any border tiles what so ever.
- First, the player must claim the tile. Once they claim the tile, they enter construction mode and a confirmation border shows up around the tile like a box, indicating that it is now under the player's control and ready for construction and this is their land. How a player claims a tile is by using an Item called "Claim Token" on the desired tile. A claim token can be purchased by traders for credits. A claim token is used once and is consumed upon use. Once the player owns that tile, they can begin constructing structures on it. When constructing strutures, zombies do not bother the player. But they can also not bother the zombies either. If they exit the tile and go a far distance, or they leave construcion mode, the protection ends and zombies can interact with the player and the environment as usual.
- Players may only build in the tile.
- If a player is next to an empty tile adjacent to their claimed tile, they may be able to extend their construction into that tile, provided they have another claim token. This allows for gradual expansion of the player's controlled area while maintaining the integrity of the claimed land system.
- Claim tokens last for 30 days since the time the user last visited the claimed tile. After 30 days, the claim token expires, and then the structure can be tore down for scrap by other players. They cannot rebuild on that tile until a new claim token is used, when a new claim token is used, it deletes the previous claim and establishes a new 30-day period of ownership with the new owner.
- For this update, I just want to focus on the structure building and all related mechanics, leaving other aspects such as placing down workbenches, furniture and other interactive objects for future updates.
- Zombies can attack your structures, they will not usually attack your structure as when you are in a structure sound and light is muffled, making it harder for them to detect the player inside. However, if the structure is not airtight or if the player is outside, zombies will actively seek out and attack the structure. Airtightness can be compromised by missing walls, broken windows, or other structural damage, making it crucial for players to maintain their buildings to ensure maximum protection against zombie attacks.
- Players can place a storage box in their claimed tile which they can store things in. Each storage box gets a unique inventory. You can store as many items as you like. Other players can break down your door to access your storage box if they have the means to do so, adding an element of risk and strategy to how you protect your valuable items.
- Door can be placed inside of door frames and locked to prevent unauthorized access. Only players with the appropriate key or permission can unlock and open the door, adding an additional layer of security to the player's claimed tile.
- Baricades can be placed on windows to reinforce them and prevent zombies or other players from easily breaking through. This adds an additional layer of defense to the player's claimed tile, allowing them to fortify vulnerable points in their structures.
- Curtains can be placed on windows to provide privacy and block light. An important factor to keeping the player safe and unobservable by zombies from the outside. If the player doesn';t have curtains, zombies will try to attack their front door.
- Zombies will always try to attack the front door first, if the front door is not accessible to them after repeated attempts, they will collectively try to instead attack a wall. 

## Improved Zombie AI (medium priority)

- Zombies need to move around and act a lot more like zombies. Right now they just stand in place and do nothing until the player finds them. We need to develop a system where zombies can be walking around, and detecting the player based on sound, sight, and other environmental cues. This will make the game more challenging and immersive, as players will need to be more cautious and strategic in their movements and actions.
- Zombies are very slow and lumbering, making them less of an immediate threat but more of a persistent danger. Their slow movement requires players to plan their actions carefully and use the environment to their advantage, as rushing into a horde of zombies can still be fatal despite their lack of speed.
- Zombies should have a sense of territory and be able to remember areas where they have encountered players before. This will make them more strategic in their attacks and create a more dynamic and challenging gameplay experience.
- The zombies cone of vision should be limited and directional, meaning they can only see within a certain angle and distance in front of them. This will make stealth and careful movement more viable strategies for players, as approaching zombies from outside their cone of vision will reduce the likelihood of being detected.
- Zombies should also have a sense of hearing, allowing them to detect players based on noise generated by movement, actions, or environmental interactions. This will encourage players to be mindful of the sounds they make and use stealth tactics to avoid attracting zombie attention.
- Zombies should be able to communicate with each other, either through vocalizations or other means, to alert nearby zombies of the player's presence. This will create a more dynamic and challenging environment, as players will need to consider the potential for reinforcements when engaging with zombies.
- Zombies need to shuffle around the map, maybe fight eachover. Maybe they group up together.
- Add sounds for the zombies, including groans, footsteps, and attack noises, to enhance the immersive experience and provide players with auditory cues about nearby threats.
- The way that the zombie attacks right now is not very convincing as basically the animation does not sync up directly to when the zombie hits. So they can kill you very unfairly while it looks like they are just completely standing still, or their animation haven't actually triggered yet. We need to change how the zombies attack so their attacks are much more like a "swing" and you can dodge it, making combat feel more fair and responsive.
- The swing or lunge the zombie takes should fire just one attack event, ensuring that the damage is applied at the correct moment in the animation and making it possible for players to dodge or block the attack.
- Make the zombies damage a bit less but also take into account if a user has no armor, ensuring that unarmored players are still at significant risk while armored players have a better chance of surviving encounters.

## Expanded Armour

- We need to expand armour in the game so there are three types of armour: light, medium, and heavy. Light armour provides minimal protection but allows for greater mobility, medium armour offers a balance between protection and mobility, and heavy armour provides maximum protection at the cost of reduced mobility.
- We need to implement these new attributes into the current jobs, ensuring that each job has appropriate access to light, medium, or heavy armour based on their role and gameplay balance.
- Light armors also provide increased agility and stamina, allowing players to move faster and perform actions more efficiently compared to medium and heavy armors.
- Medium armors provide a balance between protection and mobility, offering moderate defense while still allowing players to move relatively freely compared to heavy armor.
- Heavy armors provide maximum protection but significantly reduce mobility, making players more resilient to damage but slower and less agile compared to those wearing light or medium armor.
- Heavy armors have more damage resistance but also have an impact on your movement speed
- Heavy armors also reduce stamina regeneration, making prolonged physical activity more challenging compared to lighter armors.
- Consider adding special abilities or bonuses for each armor type to further differentiate their gameplay impact, such as increased carrying capacity for heavy armor or faster sprinting for light armor.
- Medium armors are the best of both worlds, providing a balanced mix of protection and mobility without the extreme drawbacks of light or heavy armor.
- Light armors provide the best mobility and agility, allowing players to move quickly and perform actions efficiently, but they offer the least protection compared to medium and heavy armors.
- The better you are at light armors, the better armors you can wear and also the less mobility penalty you will suffer when wearing heavier armors. 

## Expanded Attributes

- Add missing attributes "Pistols" and "Explosives", rename "Snipers" to "Rifles". 
- Apply new attributes accordingly into the job system

## Improved Job Selector UI

- Improve the current job selector UI in the menu to make it nicer and more user friendly, using boxes to seperate each job and making it more clear which job you are choosing. Maybe we could instead lay out the jobs in a grid? So they each have an icon, then when you click on one, the right panel displays detailed information about the selected job along with a backstory for each job which I will write but just use a placeholder for now.
 - Maybe it breaks down each attribute you get into a nice table

## World Generation Rules (last)

- I have added building_ra buildings to the buildings folder with the intent that these buildings and these buildings alone are the only ones to be used in radiation zones. This same rule applies to the new skyscrapers too. I do not want normal buildings to spawn in the radiatioactive areas. Radioactive zones are to only use ra buildings. If none are available, then ra cells should place just a terrain or detail tile appropriately. 
- This rule that buildings must equal their environment tags only applies to military (army_base) cells, and radiation cells. Everything else buildings which don't have a tag may appear.
- If a tagged building is available for a specific environment, it will take priority over untagged buildings when generating the world.
- Please make sure all new building changes are staged to gmod along with associated materials and models

## Refactor and Optimisations

- Refactor cl_skybox.lua and decrease the amount of lines in the file. Possibly split up functionality into a module like atmosphere module.
- I notice that around the project we are using  IsFiniteNumber, IsFiniteVector, and similar utility functions. Consider creating a util script file to centralize these checks and reduce code duplication. Check all files for repeated patterns and refactor accordingly.
  - Also, finiteNumber and IsFiniteNumber are both existing. Consider consolidating them into a single utility function to maintain consistency across the project. Check for Vector and angle equivalents as well.
- Rename "materializer" and any mentions of materialization and materializer to "spawner" and "spawning" where applicable.
- readJson and readJsonFile both exit, consider creating a util script and centralizing JSON reading functionality to avoid code duplication and ensure consistent error handling.
- There is a data static in the root of gmod: C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\data_static and also in our gamemode. Please make sure there is no data_static in the root of gmod and that all files are being put into our gamemode contents data_static, as I am unsure if the data_static at the root is even read, and also it won't be shipped with our gamemode

## Fixes

Due to our 3rd person camera system we are having issues with source culling and it thinking objects are not in the players view. This is also breaking our zombie system sometimes as zombies can seem to despawn in front of your eyes sometimes. Investigate a way to fix source culling so items props behind walls which are visible from above do not disppear and the false positive it brings to our zombie materializer
