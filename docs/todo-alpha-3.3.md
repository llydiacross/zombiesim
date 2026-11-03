# Alpha 3.3 - Phased Implementation Plan

**Archived 2026-11-02:** unfinished work is carried into the active
[Alpha 3.5 tracker](../todo-alpha-3.5.md). This archive is a historical
record, not a declaration that Alpha 3.3 was released or fully accepted.
Later dated evidence supersedes earlier active-status and next-step notes.

**Historical status: ACTIVE IMPLEMENTATION - PHASE D, 2026-10-30.** The user accepted
Phase C with the limits recorded below and asked for uninterrupted progress.
The requested world-map AFK behavior has received the bounded live review
recorded below. Continue Phase D, preserving the explicit guard-testing
deferral and resolving phase-specific design questions. This does not authorize world regeneration,
compilation, broad staging, a maintenance batch, production changes or
publication. Get explicit acceptance rather than equating a passing test
with visual or gameplay approval.

**World-map AFK request:** the user chose the normal three-second countdown,
damage interruption and exit grace. The map now uses the existing AFK owner
from M, the Tab menu and `zombiesim_map`; closing it participates in the
shared menu heartbeat. Rapid cancellation and reopening during an outstanding
leave are covered. Focused offline map/AFK fixtures pass 13/13 and GLua syntax
passes 380/380. After an approved preview reload, the isolated in-game AFK
suite passed 14/14; the survivor's cell, attributes and inventory matched
the pre-reload checks. The user confirmed M cancellation, an open map retaining
AFK for at least eight seconds, M/X close with grace and restored controls,
the Tab-menu map and rapid reopening. Damage interruption was tested in the
isolated suite, not by damaging the survivor; firing during grace, the console
entry and multiplayer remain unverified live.

**A3 accepted, 2026-10-30:** the user accepted the editor/explorer work with
the stated limits: detailed dirty-tab close paths and resolution changes
were fixture-tested but not separately reviewed live. The user confirmed the
overall editor and prefab-wide preview height work. A2 resumes; the
editable-prop ground-shadow issue remains deferred to the end of Alpha 3.3.

**Guard verification deferred, 2026-10-30:** the user asked to progress
faster and skip further guard testing because guards will not be used until
later. Stop the guard kill/corpse-reward probe (its two live runs never
reached the Walker `OnKilled` callback; a likely cause is firing on the
Walker's spawn tick). Keep guard export and normal world spawning blocked.
Retain existing guard source, fixtures and the user's `testguard` document;
do not claim actual guard kills, rewards, deployed-world guards or
multiplayer guard behavior. Resume these checks only when guards are needed.

**A2 accepted with limits, 2026-10-30:** the user accepted A2 and moved to
Phase B. Retained, explicitly unverified limits: multiplayer consistency;
normal-world non-unit scaling (still blocked; isolated fixtures only); a
road blockade/gate set piece in a real cell (isolated placeholders only);
accepting a prefab-prop loot reward in a real city cell; and all deferred
guard runtime checks. These are not cancelled and must not be claimed.
**1x1 road redesign:** the user reports that the 1x1 roads have been
redesigned for aesthetics and that a full world recompile is required. Treat
existing compiled worlds as not yet reflecting those edits. Preserve the
user's road VMF/VMX sources, including new files, and inventory their actual
dependencies and affected output profiles in Phase H. Plan the requested
full recompile with its required matching derivatives and visual review; get
separate approval before generation, compilation, staging or any production
output. No recompile has been run for this redesign.

**World-source requests, 2026-10-31:** the user updated both launcher VMFs,
added prefab anchors and visuals to many roads, edited many building tiles
and added road-connection entities. Preserve every authored VMF/VMX. New
connection rules: support `parking` and `dual_driveway`; connections must
modify the adjacent ordinary road tile, including from 1x1 buildings.
Priority per road tile: two driveways become a dual driveway; driveway beats
parking and bus; parking beats bus. The user's new `edges/tile_edge_ocean_*`
pieces (640x640, `nature/blendrocksand004a` top) replace the omitted outer
ring slots on **every** west-ocean cell, only in edge spaces adjacent to the
ocean, with the physical shell and skybox shoreline moved out to that outer
edge so the coast joins seamlessly. The dancer head work (D3) is deferred.
These edits need the same separately approved full-world recompile; nothing
has been generated, compiled or staged for them.

**World-prefab addition, 2026-10-30:** the user approved one explicit world
placement per prefab: profile, logical cell (initially the current editor
cell), centred core tile X/Y, surface-relative XYZ offsets and world rotation.
This is not a tag. Normal gameplay reads explicitly exported addon definitions,
not editor DATA overrides; no map rebuild is needed. The user reconfirmed that
these prefabs must be exported. The existing dry-run/`-Apply`/`-Replace`
exporter now validates and preserves placement settings, and the normal core
package includes them. No saved user prefab has been exported by this change.

**First control review:** the user reported Scene prefab offset `(20,0,0)`
did not move the grid. The new offset moved objects, but grid/compass XY still
used the unshifted base origin. Source now moves both guides with horizontal
prefab offsets while leaving reference geometry and the previously approved
reference-surface guide height unchanged. The exact20-unit case, compass,
tab restoration and unchanged local prop coordinates pass editor53/53;
GLua376/0 passes. The running `gm_flatgrass` editor has one owner and no
survivor and still has the previous source. Preserve its tabs; use the existing
snapshot-preserving Change Map flow or obtain saved-work consent before
reloading. Verify the grid movement visually after fresh load before claiming
the correction accepted.
The user used the snapshot-preserving map change and confirmed the grid now
moves correctly. Separate status confirms `gm_construct`/preview, one owner
and no loaded survivor. They selected `test123` for export, but its saved
DATA copy has no `worldPlacement` and includes a movable bench at scale1.4.
Only a dry run ran; no export was written and the saved document is unchanged.
Choose an enabled unscaled world prefab, or explicitly settle the separate
normal-world scaling gate, before a gameplay test. The dry run exposed an
exporter variable collision between prefab ID and per-prop ID; renaming the
per-prop local fixes reporting/temp filenames, with export67 assertions passing.

**Editor save/layout regression:** the user next selected the unscaled `test`
stool, but saving reported an existing ID and the screenshot showed metadata
entries displaced below Save/Delete. No export ran; saved `test` still has no
placement. Source now gives the Prefab form and world-placement controls
unique docking positions, refreshes metadata with `SetText` so a focused
`DTextEntry` cannot retain another tab's value, and binds saved-tab IDs to
their opened identity when synchronizing metadata. Existing-ID protection
remains intact. The fixture now models scroll-panel canvases and the native
focused-entry `SetValue` behavior. Editor55/55, explorer10/10, transfer2/2,
map-contract2/2 and GLua376/0 pass, including failed/successful saves and
focused saved/draft tab switches. This is source/offline evidence, not live
acceptance. Read-only status confirms `zz_preview_d56e6ff2981a`/preview,
one editor owner and no loaded survivor. Preserve all open drafts; use the
snapshot-preserving Change Map flow to load the fix, then review the metadata
layout and retry saving the intended `test` tab. Do not export until its
saved identity and enabled placement are independently verified.

**World-prefab live review completed:** the user confirmed the corrected fields
and saving after changing maps. An initial disk read still showed the old
unplaced `test`; after a separate save confirmation the stored document was
independently verified with enabled preview placement at logical `(4,-11)`,
tile `(0,0)`, offset `(0,1,0)`, zero rotation, and one stationary unscaled
stool with loot Off. Only this document was explicitly exported; dry-run,
applied export and installed-file SHA-256 all match
`444D42F243EF8B8013F6A35555F39834ECC93D2C6591C5487F192EF30764F5FA`.
After Return to Launcher, separate status confirmed no editor/survivor,
all session/transfer markers were absent, and the stored city/preview
baseline exactly matched before gameplay deployment.

The user authorized using their existing preview survivor for a bounded visit
and restoring the starting cell. Separate state confirmed deployed logical
`(14,0)`/cell302 on `zz_preview_ed3d3fa48090-cp`. Normal world travel reached
`(4,-11)`/cell28 on `zz_preview_d56e6ff2981a`, with no editor session.
The runtime reported exactly one `test` instance, stable anchor `world_test`,
one prop, no pending initialization or prefab error. The user confirmed the
stool is visible, correctly placed and has working walking collision.
Normal travel restored `(14,0)`/cell302 and the original map; a separate
report confirmed zero prefab instances there and health100. City persistence
and preview attributes match the pre-visit snapshot; stored preview changes
are limited to ordinary Hunger/Thirst, Revision and UpdatedAt. Do not claim
the whole survivor hash stayed identical during normal gameplay.
The exported `test` remains enabled at the reviewed placement.

The user approved a separate same-BSP control and target revisit. Logical
`(7,-9)`/cell79 uses the same `zz_preview_d56e6ff2981a` BSP as `(4,-11)`/
cell28, but reported zero anchors and props. After an intermediate return
through `(14,0)`, a second target load reported exactly one `world_test`
anchor and one prop. Normal travel then restored `(14,0)`/cell302 on
`zz_preview_ed3d3fa48090-cp`, with zero prefab instances and health100.
City persistence, preview attributes and stable preview character fields
matched the pre-visit snapshots. Hunger/thirst continued ticking and normal
level transitions replenished stamina from approximately12.89 to140; these
were not restored artificially. This checks separate loads of the same BSP
for two logical cells, not a direct same-BSP-to-same-BSP gate transition.
Multiplayer, scaled spawning, accepted loot rewards and full A2 acceptance
remain open. No map rebuild, world regeneration, production change or
publication ran.

The installed preview world data contains no accessible adjacent cell pair
sharing the same BSP, so that direct live gate case is unavailable without
changing the world. The existing transition fixtures explicitly verify that
gate travel requests a forced reload and that the same-map reload is queued.
Their first launcher run passed those cases but failed three arrival cases
because the fixtures did not model the existing asynchronous Walker preload.
The tests now hold and explicitly complete a fixture preload before checking
city/den fades and movement; no travel behavior changed. After a clean
launcher reload, live `zn_test_safezones` passes 27/27 and GLua376/0 passes.
This is fixture evidence, not a direct same-BSP gate traversal.

**Deferred foliage report:** in the restored preview cell `(14,0)` on
`zz_preview_ed3d3fa48090-cp`, the user reported a tree in the road. The
fresh view at `data/zombiesim/screenshots/foliage_tree_on_road_20261030_retry.png`
shows a tree trunk occupying the roadway. Its owner and cause have not been
investigated. Preserve this evidence and defer the foliage issue until the
end of Alpha 3.3 as requested; do not change foliage or regenerate the world
during the prefab phase.

Source implements automatic placement through `ZM_Prefabs`, before loot,
including maps with no compiled anchors, stable world-prefab loot/effect
identities and owned-anchor cleanup. Profile/logical-cell matching prevents
other logical cells sharing a BSP from inheriting the placement. All selected
tile surfaces are detected before spawning new content. Disabled world
prefabs retain their settings and are excluded from tag selection; conversion
back to a tag prefab removes placement metadata. Changes require explicit
re-export and a cell reload/map cleanup; deleting only the DATA document does
not unpublish an earlier export. Existing normal-world scale restrictions,
survivor isolation and production/publication gates remain unchanged.

The editor now offers suggested tags, including `burningCar`/`burningBarrel`
and custom library tags, while retaining custom text. Tags do not create fire.
The explorer offers the same filter suggestions and displays placement kind
and location. Compact prefab-preview X/Y/Z offsets move the entire prefab
relative to the reference without changing prop-local coordinates; per-tab
and map-transfer state retain them. Placement capture explicitly copies these
offsets; world rotation applies on gameplay cell load, not to the local editor
preview. These controls need fresh-load human review.

Offline prefab runner35/35, editor53/53, explorer10/10, document13/13,
storage11/11, catalog4/4, owner17/17 and spawn10/10 pass. Export66,
packaging70 and GLua376/0 pass. After independently confirming the empty
preview launcher, a same-map reload loaded this source; fresh live
`zn_test_prefabs`28/28 and `zn_test_prefab_spawn`7/7 pass. The latter creates
a real temporary `zn_prefab_anchor` with no compiled map ID and verifies
native transforms plus stable loot/light IDs. It does not prove automatic
placement in a deployed cell, gameplay loot/search, visible placement,
multiplayer or visual UI acceptance. No compile, world regeneration,
production edit or publication ran.

The final read-only survivor comparison after the preceding cell review
matched the recorded city/preview persistence baseline. Separate status after
the fresh reload confirms `zn_preview_start`/preview, one human, no editor
owner/participant and no loaded survivor. Next: review the new controls and
choose an explicitly saved/exported world prefab for a bounded real-cell check;
do not export `testguard` or another user document without selection.

**Additional requests, 2026-10-30:** add a Change Map button beside Return to
Launcher in the prefab editor, with a thumbnail browser recommending
`gm_construct` and `gm_flatgrass` and a way to select custom maps. The user
chose to restore every open tab, including unsaved edits, across the map
reload. Show mounted custom maps separately with a placeholder when a
thumbnail is unavailable; preserve the preview-only session and survivor data.
Also add a directly placeable Hammer guard entity, exposing clothing and
other agreed guard settings in Hammer and the prefab editor. The user chose
per-guard damage per shot, fire rate and accuracy controls as well as the
previously agreed settings; guards remain invulnerable with unlimited ammo.
Reuse the
server-authoritative guard behavior and validation; this request does not
authorize generator changes, map compilation or staging.

**A2 guard decisions, 2026-10-30:** start with stationary, named,
non-interactive guards using clothing-compatible citizen models. The user
chose invulnerable guards that zombies do not target, a selectable compatible
weapon and author-configurable engagement range per guard, no fixed guard
cap (with a performance warning), and a selected idle animation that combat
interrupts and then resumes. Determine actual supported models, weapons,
animation and clothing behavior before claiming engine compatibility.
For the first weapon slice, the user chose a small verified subset. Guards
turn in place toward targets and return to their authored facing, cannot harm
survivors or friendly NPCs, and guard kills can produce enemy loot without
awarding player XP. Existing enemy rewards currently require a player killer,
so that loot behavior needs an explicit guard-specific path. The user chose
the normal enemy drop chance and item levels interpolated across each item's
allowed range by danger, without player bonuses. Preserve the existing
separate guaranteed maximum-level boss reward. After the unattended-farming
consequence was explained, the user chose unlimited guard ammunition.
The guard-specific reward foundation is implemented without spawning guards:
ordinary guard kills use the existing drop roll and danger-scaled item level,
while guard boss kills preserve the boss reward and finish its lifecycle.
Offline guard-reward3/3 and GLua353/0 pass. In the freshly reloaded preview
launcher, live loot13/13, enemies14/14 and bosses6/6 pass, including the
new guard reward cases; stored city/preview persistence still matches the
baseline. No guard entity, editor controls, actual guard combat or A2
acceptance is implied.
The first bounded guard-model probe found the clothing-compatible male citizen
model, idle sequence and right-hand attachment, but its suite failed because
it asserted removal in the same frame as `Entity:Remove`. Removal may be
deferred. Change the probe to verify cleanup in a separate request after the
frame, rerun it, and do not treat this failure as an actor/animation pass.
The cleanup check now runs as a separate request. Offline deferred-removal and
failure-cleanup fixtures pass; fresh live model1/1 and cleanup1/1 pass. For
`models/player/group01/male_03.mdl`, the engine reports `idle_all_01` index2,
right-hand bone11, attachment5, and `idle_pistol`/`range_pistol` plus
`idle_smg1`/`range_smg1` sequence names. This is metadata only: it does not
prove visible animation, attachment placement, clothing, combat or any other
model. GLua354/0 passes.
The next bounded probe tests whether a temporary non-player model can fire a
nonlethal, damage-filtered shot at a temporary walker. It is restricted to
the sole-human editor workspace, removes both entities and verifies their
removal separately after the frame. Offline authorization, friendly-damage
filter, failure cleanup and deferred-removal fixtures pass; GLua355/0.
A launcher invocation correctly rejects the missing editor session. Ask the
user to open the editor before running the probe; no survivor or prefab
document is altered.
The user opened the editor; separate status confirmed `gm_flatgrass`/preview,
one owner and no loaded survivor. Live shot1/1 confirms a temporary
non-player model's damage-filtered shot hit a temporary Walker nonlethally;
post-frame cleanup1/1 confirms both temporary entities were removed.
This proves only that engine path, not an actual guard, weapon presentation,
friendly-fire safety against real players, or multiplayer. The editor remains
open; check for unsaved work before any later reload or return.
Source now has a guard-targeting primitive that chooses the nearest visible
living Walker/boss, bounds engagement by range, and filters bullet damage to
the chosen target. The owner-only shot probe now exercises that primitive.
Offline targeting2/2, guard-reward3/3, probe safety/cleanup fixtures and
GLua357/0 pass; the new primitive has not yet been loaded or fired in-engine.
Confirm the current editor state and obtain consent before reloading it.
The user confirmed their work was saved and approved the reload. Fresh status
confirmed the same sole-owner/no-survivor workspace; the real targeting
primitive's nonlethal engine shot passes1/1 and post-frame cleanup passes1/1.
Target selection and friendly-fire filtering remain offline-fixture evidence,
not actual multiplayer verification. No guard entity or prefab authoring is
implemented yet.
An initial, not-yet-authored guard actor and sole-owner editor preview now
exist in source. The actor uses a clothing-compatible citizen, an existing
firearm's validated stats, stationary target selection, invulnerability,
and idle/combat transitions; the preview owns a high-health temporary Walker
and cleans up on stop, disconnect, map cleanup or five-minute expiry.
Guard actor3/3, config1/1, weapon1/1, targeting2/2, reward3/3, probe2/2,
clothing-queue1/1 and safety fixtures pass offline; GLua367/0 and Workshop
packaging fixtures69 pass. None of the actor, outfit, weapon attachment or
animation has been live-loaded or visually accepted. Its normal prefab
authoring/spawning path remains absent. Obtain consent before reloading the
current editor, then verify the weapon registry and guarded preview before
asking for visual review.
After a user-approved editor reload, both candidate weapon records resolved
in-engine and the isolated guard fired at the temporary Walker (26 shots,
312 health lost at the first status). The user reported outstretched/T-pose
arms while shooting; the Walker's very high health was intentional for the
nonlethal preview. The guard, Walker and weapon were stopped and a separate
status reported zero remaining entities. The firing sequence is currently
reset as the whole-body sequence; investigate using a gesture layer over the
weapon idle instead. The editor remains open and may contain unsaved work.
Source now layers and reuses the firing gesture over the weapon idle, removes
it on combat exit and restores the authored idle/facing. Offline guard actor3/3,
probe2/2 and the complete guard fixtures pass; GLua367/0. GMod documents
`anim` scripted entities as `BaseAnimatingOverlay` and the sequence/gesture
layer APIs at `wiki.facepunch.com/gmod/BaseAnimatingOverlay` and
`wiki.facepunch.com/gmod/Entity:AddGestureSequence`. This is a hypothesis
for the reported pose, not a visual fix until a fresh human review.
After a user-approved reload, the guard fired with a live gesture layer and
the user reported that the gun faces the wrong way. They did not explicitly
accept the body pose. The preview was stopped and status confirmed zero
remaining owned entities. A preview-only orientation control and muzzle
alignment diagnostic are now in source; focused guard fixtures and
GLua367/0 pass. Reload only with consent, inspect the exact attachment/model
relationship, then test the corrected orientation and seek human review.
The user clarified that the barrel pointed back toward the guard. On the
temporary pistol only, local yaw180 made the barrel point toward the Walker;
the user reported that the grip still does not sit correctly in the hand.
The numeric muzzle-position alignment was not enough to prove the visual
orientation. The preview has been stopped and status confirms zero owned
entities remain. Test the documented engine bone-merge attachment before
committing an offset; the body pose has not yet been explicitly accepted.
An owner-only, reversible bone-merge comparison is prepared. The normal
attachment transform is saved and restored when the comparison is disabled;
server muzzle alignment is explicitly not treated as proof for client-side
bone merge. Focused guard fixtures and GLua367/0 pass. A fresh editor reload
with the user's consent and a human hand/weapon review are still required.
After a user-approved reload, the user confirmed the bone-merged pistol sits
correctly in the hand, points forward and the arm pose looks right. Source
now uses bone merge for guard weapons; focused fixtures and GLua367/0 pass.
The reviewed pistol comparison was stopped and status confirmed zero owned
entities remain. The source change itself and the SMG attachment have not
yet been reloaded or visually checked; normal prefab integration is still open.
After a user-approved reload, the source-backed pistol preview reported bone
merge and an active firing gesture; the user confirmed its hand placement and
pose. A separate SMG preview fired and the user confirmed its weapon, pose
and sound look right. Two sampled SMG status reports showed `firingGesture`
false despite increasing shot counts; do not infer gesture lifetime or
animation correctness from those samples. Both previews were stopped, with
separate status confirming zero remaining owned entities. Guard authoring,
world spawning, actual kill/reward, multiplayer and friendly-fire tests remain
open; the editor remains open with no survivor loaded.
Guard records and server content validation are being added; guard-bearing
exports and world spawns explicitly refuse until integration is verified.
The first export regression failed because its new empty-guard dry run
encountered an existing different fixture output without `-Replace`, before
checking the intended schema. Rerun the isolated fixture with explicit
replacement permission for the dry run; no installed prefab was changed.
The corrected dry run passes44 export assertions. Shared documents now
validate optional guard records and server content settings; legacy documents
gain an empty guard list without source mutation. The editor preserves the
field, while nonempty guard exports and world spawns fail explicitly until
their integration is complete. Full offline prefab runner31/31, guard
fixtures9/9 and GLua367/0 pass. Guard editing and actual world spawning remain
unwired, and these latest schema changes are not live-loaded.
After the user's subsequent return, a separate read-only status confirms
`zn_preview_start`/preview, one human, no editor participant or owner, and no
loaded survivor. The editor marker is absent and stored city/preview
persistence matches the recorded baseline.
The direct `zn_prefab_guard` Hammer point entity and shared combat override
foundation are now in source. Damage and shot spread are optional; fire rate
is an optional interval in seconds per shot (minimum 0.05). Blank overrides
retain weapon values. Shared/server validation is reused, malformed Hammer
settings fail explicitly, and existing guard records retain weapon defaults.
Offline prefab40/40, guard9/9, export44, packaging69 and GLua367/0 pass.
After a safe preview-launcher reload, live prefab24/24, guard configuration
1/1 and weapon registry1/1 pass. The marker is absent and stored city/preview
persistence still matches the baseline. This does not verify a compiled
Hammer guard, visible combat overrides, guard editor authoring or normal
prefab spawning/export; those remain open and map compilation remains gated.
The user approved one small isolated compiled Hammer guard fixture, temporary
staging and preview entry without loading a survivor. The fixture contains
two direct guard entities, one using default settings and one using a blue
shirt, black pants, SMG and combat overrides. A map-only hash-ledger staging
mode avoids installing a temporary prefab. This approval does not extend to
world regeneration, other maps, production or publication.
The isolated fixture source passes16 assertions; its compiled BSP retains both
guards and their keyvalues (33 source/BSP assertions). VBSP, VVIS and VRAD
complete successfully with 4 clusters/4 portals. Map-only staging fixtures
pass17 assertions; inspection finds both destinations clear. The fixture has
now been staged with a map-only hash ledger and entered as
`zn_dev_prefab_anchor`/preview. Separate live status confirms one owner, one
participant and no loaded survivor. Live `zn_test_prefab_guard_hammer` passes
1/1: both guards were created by the compiled map, initialized and retained
their documented defaults or explicit weapon, combat and networked clothing
settings. The user confirmed both guards and the customized
clothing and weapons look correct. Separate status after return confirms the
preview launcher, no editor participant or loaded survivor; the marker is
absent and stored city/preview persistence matches the baseline. Hash-ledger
restoration removed both staged BSPs, and the isolated generated fixture was
removed. Actual firing of the overrides and deployed-world/multiplayer
behavior remain unverified.
Guard authoring is now in source: the Place panel adds a guard, the selected
guard inspector edits citizen model, idle, name, clothing, weapon, range and
optional damage, fire interval and shot-spread overrides, and existing
transform gizmos and per-tab preview height apply. Weapon choices come from
the server; editor and explorer guard models reuse the existing budgeted
clothing queue. Offline prefab41/41, editor46/46, session16/16, guard
preview3/3, export44, packaging69 and GLua370/0 pass. These changes have not
been visually reviewed; after a safe preview-launcher reload, live prefab
25/25 and guard configuration1/1 pass. Normal guard prefab export and world
spawning remain explicitly blocked. The requested map picker and restoration
of unsaved tabs across map changes remain unimplemented.
The user confirmed the guard editor controls, appearance and explorer preview
work. They saved the review under `testguard` rather than the suggested ID;
server DATA independently confirms that document contains one guard. Preserve
it as user-owned. A separate status confirms the editor is still open on
`gm_flatgrass`/preview with one owner and no survivor loaded; check with the
user before any reload or discard, and verify launcher return and survivor
baseline after the session.
The user confirmed all three combat override checkboxes remain selected after
save/reopen. The first file snapshot preceded the final saved state and did
not contain them; a subsequent independent read confirms `damage`,
`fireInterval` and `spread` are all present in `testguard`. Do not infer a
save bug from the earlier snapshot.
The next spawn slice is fixture-only: guard actors now report deferred
initialization success/failure exactly once, and the isolated spawner waits
for all guards, applies anchor transforms and rolls back the whole fixture
on a failed guard. Normal guard world spawning and export remain blocked.
Offline guard10/10, actor5/5, prefab31/31 and GLua370/0 pass. This callback
and fixture-only spawn source has not been live-loaded; real-engine spawning,
runtime owner/loot-readiness integration and export validation remain next.
An in-memory live guard-spawn fixture is now prepared. It is restricted to
one preview-launcher admin with no loaded survivor, checks four cardinal
anchor transforms and combat overrides after deferred initialization, and
removes its temporary actors with a separate post-frame cleanup check and
30-second safety expiry. Offline guard11/11 and GLua371/0 pass.
The user saved and returned to the launcher. An initial combined status
request arrived during the transition without reports; separate follow-up
status and persistence requests confirmed `zn_preview_start`/preview, no
editor owner or loaded survivor, absent marker and the matching baseline.
After a fresh launcher reload, the real-engine fixture starts1/1, checks
deferred guard readiness, four anchor rotations and combat overrides1/1,
and verifies post-frame removal of all actors and weapons1/1. This is
isolated spawn evidence, not actual firing, prefab anchor integration,
multiplayer or city-cell acceptance. Normal spawning and export stay blocked;
preserve `testguard` and any other user work.
The prefab owner now tracks fixture-only guard readiness, defers loot until
all guards have initialized, rejects particle triggers on pending anchors,
and resumes ordinary loot after a reported guard failure. Anchor removal and
map cleanup ignore late callbacks. Offline owner15/15, spawn9/9, prefab31/31
and GLua371/0 pass. This owner change has not yet been live-loaded; normal
guard world spawning and export remain blocked.
After a fresh launcher reload, the unchanged live prefab contract25/25,
unscaled spawn6/6 and loot-spot30/30 suites pass; the deferred guard-owner
path itself remains fixture-only and has not run through a compiled anchor.
Guard weapon definitions now have one shared, packaged static catalogue for
the server/editor and export validation. Export checks guard identity,
transforms, citizen/clothing choices, weapon IDs and combat override bounds,
then still refuses guard-bearing exports until runtime integration is
verified. Offline prefab43/43, export57, packaging70 and GLua371/0 pass.
After another safe launcher reload, the live shared weapon catalogue1/1,
guard configuration1/1 and prefab contract25/25 pass.
The user separately approved one isolated four-anchor guard-prefab compile,
temporary staging and preview test. Its source passes7 assertions, compiled
source/BSP checks pass15, VBSP/VVIS/VRAD complete, and visibility is 4
clusters/4 portals. Guard-fixture staging/restoration passes20 assertions;
inspection found both map destinations and the temporary prefab destination
clear. The fixture is now staged with a hash ledger and loaded on
`zn_dev_prefab_anchor`/preview with one owner and no survivor. Synthetic-cell
spawn reports four anchors, four guards, four props and zero pending; live
`zn_test_prefab_guard_anchor` passes1/1 for transforms, readiness, weapon,
combat values and networked clothing. The bridge initially labelled the
accepted pending message as an error even though a separate status showed
completion; source now sends an explicit pending report without that
misleading error, and focused owner fixtures/GLua371/0 pass. That reporting
fix is not yet live-loaded. The user confirmed all four prefab-spawned guards,
barrels, rotations and outfits look correct. Separate return checks confirmed
the preview launcher, no editor participant or loaded survivor, absent marker
and matching survivor baseline. Hash-ledger restoration removed the temporary
BSPs and prefab, and the isolated generated fixture was removed.
Normal guard spawning and validated export are now source-wired through the
same owner and spawner that passed the isolated fixture. Offline prefab43/43,
export57 and GLua371/0 pass; a dry run of the user-owned `testguard` passes
without writing any exported file. This normal-path wiring and the pending
bridge-report fix have not been fresh-loaded. Real city-cell eligibility,
guard override firing, kills/rewards, multiplayer and lifecycle remain
unverified; do not mark A2 accepted.
For a bounded actual-firing check, the existing owner-only guard preview now
accepts validated damage, fire-interval and spread overrides, reports the
initialized weapon settings and sample time, and uses a non-player-targeting
temporary Walker with a 15-second expiry. The ordinary five-minute preview is
unchanged. Offline probe3/3, config2/2, actor5/5, targeting2/2 and GLua376/0
pass; fresh live prefab contract28/28, loot13/13 and loot spots30/30 pass.
The user opened `gm_flatgrass`/preview with one owner and no survivor loaded.
The actual pistol guard initialized with damage23, 0.2 seconds per shot and
zero spread; across two samples 2.55 seconds apart it fired12 shots and the
temporary Walker lost276 health, exactly23 per shot. All59 observed shots
corresponded to1357 health lost. The 15-second expiry removed the guard,
weapon and Walker; a separate status confirmed zero owned entities. A later
manual stop correctly reported that the already-expired probe had no owner.
City/preview-attribute persistence and the saved `(14,0)` cell match the
pre-probe baseline. The user returned to `zn_preview_start`/preview; a
separate status confirmed no editor owner or loaded survivor, no session
marker and the same persistence baseline. Actual guard kill/reward,
multiplayer and deployed-world combat remain separate.
The requested map picker is now implemented in source with recommended and
paginated/searchable mounted custom maps, thumbnail fallbacks and a custom
map-name entry. Before a map change, the client writes and verifies an exact
local snapshot of every tab; the server atomically updates the owner-bound
session marker and reauthorizes saved IDs on the destination. Dirty and
incomplete drafts are retained. Failed transitions retain recovery data,
with retry/return-to-previous-map paths; unsafe, unmounted and known
ZombieSim world maps are rejected. The server keeps preview profile and
blocks survivor loading for editor sessions. Offline map contract2/2,
transfer2/2, editor48/48, session20/20, prefab46/46, packaging70 and
GLua376/0 pass. This source has not yet been live-loaded; real thumbnail
resolution, JSON/DATA round-trip, both map transitions, unsaved-tab recovery,
UI appearance and custom-map behavior remain unverified.
The first forwarded client map-test request was acknowledged but produced no
report; a separate client light-status request confirmed the client was
ready. The new test's nested relative includes were replaced with injected
dependencies, matching the prior GMod include constraint. An intermediate
test-file syntax error and its offline harness lookup were corrected;
prefab35/35 and GLua376/0 now pass. Reload the verified launcher and rerun
the client test; do not treat the earlier acknowledgement as a client pass.
After a fresh launcher reload, the actual client test confirms exact
JSON/client-DATA round-trip and cleanup, but both recommended thumbnail
materials failed with the `../maps/thumb/` path. Public GMod map-browser
implementations use `Material("maps/thumb/<map>.png")` instead; source now
uses that path. Prefab contract runner35/35 and GLua376/0 pass. Reload and
rerun the actual client thumbnail test before assuming the correction works.
After the user resumed the paused game and the launcher was safely reloaded,
the fresh actual-client map test passes2/2: incomplete draft JSON/DATA
round-trip and both mounted recommended thumbnails. The test-owned DATA file
was removed; no prior transfer snapshot exists. The built-in
`gm_construct` BSP has 33 player starts, with first origin `(704,132,-143)`;
actual workspace tracing, multi-tab switching and visual review remain open.
The first live switch was rejected on `gm_flatgrass` because
`ZM_World:GetCellsForMap` returns `nil` for a valid map with no indexed cell;
the new check had incorrectly treated that as an error. Source and fixtures
now model this API behavior while still rejecting malformed non-table
results. Prefab contract runner35/35 and GLua376/0 pass. Separate status
confirms the editor remains open on `gm_flatgrass`/preview with one owner and
no survivor loaded; the rejected transfer file is absent. The user's test
tabs may contain unsaved work: obtain consent before reloading or discarding
them, then repeat the exact `gm_construct` switch.
The user saved and approved a same-map reload. An immediate status request
arrived during a transition with no connected admin; a separate later status
confirmed `gm_construct`/preview, one owner, no survivor and a valid workspace
at `(704,132,-143.96875)`. The marker names `gm_construct`, has no pending
transfer token, and the local snapshot is absent. The user confirmed they
retried and both unsaved tabs and their edits were restored. The editor is
still open; the reverse switch, saved-tab authorization, custom map browser,
launcher return and survivor baseline remain to check. Do not reload or
discard the user's work without consent.
For the reverse check, the user opened `testguard`, made an unsaved change
and confirmed all tabs and that edit survived the switch back to
`gm_flatgrass`. Separate status confirms one editor owner and no survivor;
the marker has no pending token, includes the `testguard` authorization and
the transfer snapshot is absent. The saved `testguard` file remains
hash-identical to its prior dry-run snapshot. The editor remains open with
unsaved work; browser appearance/custom-map review and launcher/baseline
restoration remain open.
The user also confirmed the recommended thumbnails, custom-map tab and search
look and work well. No actual third-party/custom map transition is claimed.
The user returned to `zn_preview_start`/preview. Separate checks confirm no
editor owner or loaded survivor, absent editor and transfer markers, unchanged
saved `testguard`, and a matching city/preview persistence baseline.

**Additional cell-preview request, 2026-10-30:** add a Cells tab to the
editor map picker so a prefab can be previewed on a world cell. In the
left View/camera area, show tile X/Y controls when a cell is selected.
The user specified that the default editor position is the middle of the
cell, on its crossroads, T-junction or straight-road centre piece. Settle
tile-coordinate range and whether the controls move the whole preview
workspace before implementation. The user chose the central 5x5 tiles, with
the centre at `(0,0)`, east +X and north +Y. Moving tile X/Y moves the entire
preview workspace, grid and prefab together without changing saved
coordinates. The user chose to position the workspace vertically on the
detected surface at each selected tile centre. Keep preview and survivor isolation; this
request does not authorize regeneration, compilation or production changes.
The first source pass adds a paginated Cells picker, resolves each logical
cell through `ZM_World`, and moves the whole workspace to the detected solid
surface at centred tile offsets `-2..2`. Cell identity survives map switches;
different logical cells sharing one BSP still require a reload. Recovery
preserves the prior cell and tile. Offline editor50/50,
session21/21, prefab contract runner35/35 and GLua376/0
pass; no cell-preview source has yet been live-loaded. For the first bounded
review, target the previously visited preview logical cell `(14,0)`, ID302,
whose current runtime map is `zz_preview_ed3d3fa48090-cp` and topology is a
road crossroads. Its content BSP exists; engine GAME-mount availability
has not yet been checked. No world output has been regenerated or staged.
After a safe launcher reload, the first bridge request encountered a transient
lock on its command file; a separate retry succeeded. Read-only engine status
confirms preview cell `(14,0)`, ID302, map `zz_preview_ed3d3fa48090-cp`, is
available through the GAME mount with tile size640. Fresh live prefab25/25
passes. No survivor has been loaded and no cell transition has yet run.
The user instead selected preview logical cell `(17,-11)`, ID41, map
`zz_preview_fec25b5a01e6`, whose topology is a motorway straight. Separate
status confirms one editor owner, no survivor, centre tile `(0,0)` and
workspace origin `(0,0,64.03125)`; the user confirmed the centre placement
looks correct. This is not a review of the proposed `(14,0)` crossroads.
The editor remains open. Test tile X/Y movement on the selected cell before
considering another cell or returning to the launcher.
On that motorway cell, the user confirmed the workspace and prefab move
together and sit correctly on the selected surfaces. Separate status and
marker checks verified X=`-1` at `(-640,0,68.03125)`, X=`1` at
`(640,0,68.03125)`, and X=`0`, Y=`1` at `(0,640,64.03125)`. The first
requested positive-X check was actually on X=`-1`; the later positive-X
check was independently verified. No survivor is loaded. The user has not
yet reviewed the intended `(14,0)` crossroads or all 25 tiles.
The user then switched to the requested crossroads and confirmed its centre
and open tabs. Separate status and marker checks verify preview logical cell
`(14,0)`, ID302, map `zz_preview_ed3d3fa48090-cp`, centre tile `(0,0)`,
surface origin `(0,0,36.03125)`, one owner, no survivor, no pending transfer
and no local transfer snapshot. This and the earlier motorway check are
bounded visual reviews, not coverage of all cells or all 25 tile centres.
The editor remains open with possible unsaved tabs; ask before return and
verify the marker, snapshot and survivor baseline afterward.

**User scheduling decision, 2026-10-30:** bring the prefab editor UI
refinement (A3) forward after the bounded particle slice. A2 remains open:
guard NPCs, actual city/multiplayer integration and other retained checks
are not accepted or cancelled. The user chose one left workflow panel at a
time, initially closed, with top-left **Prefab**, **Place** and **Scene**
buttons; keep the right inspector in place and allow much closer zoom.
Match the existing ZombieSim UI style and seek visual approval.
The user also requested a launcher Tools-sidebar entry for Cell Health.
Source now opens the existing preview-admin manager from that entry, returns
focus to Tools on close and retains the deployed-survivor requirement for
starting maintenance. No batch is started on open. Offline launcher entry/
lifecycle2/2, Cell Health contract6/6 and GLua352/0 pass; a fresh launcher
and human UI review remain pending.
The first A3 source pass adds the requested initially closed, mutually
exclusive workflow panels using the ZombieSim skin and palette, moves
reference/fog/dark controls into Scene, keeps the right inspector, and
extends camera zoom from 350 down to 64 units. The loot-group text field is
now a sorted selectable registry list with an explicit Model default option;
server-side validation is unchanged. Offline editor36/36, session13/13,
explorer7/7, launcher entry2/2, Cell Health6/6 and GLua352/0 pass. This is
not yet live-loaded or visually accepted; test panel/close paths, input,
zoom, selection, saved/unsaved flows and the launcher entry after a fresh
preview load.
The user expanded A3: make the right inspector context-aware and tidy,
avoid always showing irrelevant rotation/settings, consider inline X/Y/Z
position and rotation rows, put camera/grid options in their own workflow
area, and refine the prefab explorer's UI as well. They also asked for
multiple open prefab documents with tabs along the top. The unused DFrame
top padding was already removed in source but that change is not yet
live-loaded. Preserve all existing saved prefabs and the sole-human editor
guard.
The user chose to focus an existing tab rather than open the same saved
prefab twice; retain independent unsaved documents and per-tab view/preview
state; prompt Save/Discard/Cancel when closing a dirty tab; and open a new
blank tab when the last tab closes. Use one View panel for camera and grid,
with zoom, yaw/pitch, reset and pan. Shift+right-drag pans while ordinary
right-drag orbits and middle-click rotation reset stays intact. Grid and
compass visibility, adjustable grid spacing and existing snap settings belong
in View; the authored 640-unit workspace guide remains unchanged.
The user also requested a reference-tile height control and chose to move
only the reference tile, not prefab objects. The offset is editor-preview
state remembered per tab, not saved in the prefab or applied in the world.
Multi-tab source keeps server authorization for every open ID, correlates
asynchronous requests with their originating tab, restores each tab's
document and preview state, and protects dirty tabs on close or exit.
Pending loads also block exit. The View panel, reference-only height offset,
context-aware inspector with compact axis rows, and themed explorer are now
implemented in source. The complete prefab runner passes31/31, including
editor44/44, session14/14 and explorer8/8; GLua352/0, launcher Cell Health
2/2 and Cell Health contract6/6 also pass. These are offline results, not
live acceptance. A read-only status confirms `gm_flatgrass`/preview, one
editor owner and no loaded survivor. Obtain consent before reloading or
discarding any unsaved work.
The user confirmed the previous work was saved and approved a same-map
reload. Fresh status again reports `gm_flatgrass`/preview, one owner and no
loaded survivor; a local screenshot shows the new toolbar, tab row and
selection-empty inspector. The client console log is stale, so it is not
evidence of an error-free load. Human interaction/visual review of tabs,
inspector, View, reference offset and Explorer is the next gate; do not
overwrite the user's saved prefabs.
The user gave a positive overall editor review and requested a second Scene
height control for the prefab as a whole. They explicitly chose preview-only
behavior: it does not change saved coordinates or world placement. Source
now offsets props, selection/gizmos, light previews and continuous/triggered
particles together, separately from the reference, with independent per-tab
state. Offline editor45/45, light preview1/1, particle preview4/4 and
GLua352/0 pass. After the user confirmed their work was saved and approved a
fresh reload, they confirmed the new prefab height preview works. The live
`zn_test_prefabs` contract suite passes23/23. The user returned through the
editor UI. Separate status confirms `zn_preview_start`/preview, no editor
participant and no survivor loaded; the marker is absent and the stored
city/preview persistence hash matches the baseline. Formal A3 acceptance
and any unreviewed resolution/close-path limits remain separate.
The first fresh screenshot showed the workflow buttons but also exposed
default bright list backgrounds and the DFrame's unused title padding.
Source now styles editor lists with the existing dark/red palette and removes
that padding so the toolbar reaches the top edge. Focused editor36/36,
explorer7/7 and GLua352/0 pass. This last styling change is not yet
live-loaded; ask before reloading the current editor and preserve any
unsaved work.
After a fresh launcher reload, the actual-client launcher Tools suite passed
8/8. The user confirmed the Cell Health entry opens, all batch categories
are unchecked, and closing returns to Tools; no batch was started. Editor
screenshots now wait for VGUI so the new controls can be inspected in a
capture; its focused offline case and GLua352/0 pass. The launcher was
reloaded again with no survivor loaded. Open the editor for A3's human visual
and interaction review; the user's saved prefabs remain untouched.

**User deferral, 2026-10-29:** stop investigating missing ground shadows
from editable prefab props and defer that issue to the end of Alpha 3.3.
Continue other approved work; do not treat the spotlight slice as visually
accepted or reopen this investigation early. Its incomplete replication,
visibility and performance checks remain recorded below.

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

The [Alpha 3.2 tracker](todo-alpha.3.2.md) is archived, **not released or
fully accepted**. The user accepted motorway live gate/alignment checks and
the current default-off CSM checks; do not redo them without new evidence.
Its full-world outputs, precise skyline replacements/revision hashes,
motorway-cleanup compile/live validation, Cell Health maintenance execution,
and carried Alpha 3.1.5 Phase D/I closure remain deferred. Record their status
and ownership at the end of this plan; do not block prefab work with a full
rebuild or pretend archival completed them. CSM's separate backlog remains
deferred in [its technical tracker](csm-implementation.md).

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
- `assets/scoreboard/callingcards` contains the user's dirty-paper pattern,
  creeper/weed symbols and five initial generated-design recipes. The paper is
  byte-identical to the existing default background; both symbols have
  transparency. The scoreboard draws background and detail separately.
  The installed catalogue has only the two defaults; the five designs are
  isolated previews and have not been staged.
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

**Additional-model scale check:** the isolated launcher spawn suite now also
measures the user's `models/props_c17/bench01a.mdl` at 1x and 1.4x on all
three axes, stationary and movable, against the same 5%-or-0.5-unit rule as
the existing drum checks. The saved `test123` document is not modified.
Focused offline fixture coverage verifies the full model/scale/axis/motion
matrix, both sides of the 5% threshold, cleanup and rejection outside the
preview launcher; GLua376/0 passes. These are fixture results, not native
bench-collision evidence. With user consent, the survivor was returned
from `(14,0)` to the preview launcher; one admin and no loaded survivor
were confirmed, and fresh `zn_test_prefab_spawn` passed 7/7 including the
native bench X/Y/Z checks. The saved return cell remained `(14,0)`, the
editor was closed, prefab status was empty, and `test123` retained its hash.

An isolated `-ScaledBench` staging option is prepared for five movable 1.4x
bench instances at the retained compiled fixture's anchors. Matched trace
reports now forward the actual prop count and keep missing/failed samples
explicit. Offline owner18/18, focused client/scale checks, staging23/23
and GLua376/0 pass. With separate user approval the retained fixture was
temporarily staged and entered with one owner and no loaded survivor. Five
anchors produced five benches; matching client/server X-axis traces before
and after interaction differed by at most 0.018 units. The user confirmed
visible size, walking and pushing. After owner-only return, the launcher had
no editor session or active prefabs, the saved cell was `(14,0)`, city and
preview-attribute persistence matched the pre-fixture baseline, and `test123`
retained its hash. Both BSP copies, the temporary prefab and ledger were
removed and independently verified absent. This is one-client, isolated
bench evidence, not actual PVS leave/re-entry, multiplayer, deployed-world
collision or permission to enable normal scaled spawning.

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

**Spotlight pool groundwork:** an isolated client pool now validates supplied
visible candidates, chooses at most eight by camera distance with stable ID
tie-breaking, and enables shadows only on the nearest. It removes the former
shadow before enabling the next, refreshes changed settings and supports an
explicit scene refresh for the editor projector-timing issue. Missing texture,
allocation failures and invalid input return errors and clear owned lights.
The [FOV](https://wiki.facepunch.com/gmod/ProjectedTexture:SetFOV) must be
strictly between 0 and 180; the
[near plane](https://wiki.facepunch.com/gmod/ProjectedTexture:SetNearZ) is
nonzero, and [Update](https://wiki.facepunch.com/gmod/ProjectedTexture:Update)
belongs in the opaque render phase. Offline pool5/5, full prefab runner21/21
and GLua322/0 pass. This is not yet included or called by the game: candidate
visibility, authoritative/networked light data, editor controls, persistence,
export, runtime ownership, scene-refresh triggers and lifecycle hooks remain
unimplemented. Integrate and test those before any live or visual acceptance;
the existing chest lamp and CSM are unchanged.

**Spotlight data slice:** schema-1 documents now optionally contain a list
of independently identified spotlights with local position/rotation, RGB,
brightness, cone angle and range. Legacy documents retain no lights; save,
reload and explicit export preserve the authored data. Validation rejects
duplicate IDs, non-finite transforms, invalid RGB, negative brightness,
FOV outside `0.001..179.999`, brightness above 1,000,000, and range outside
`8.001..1,000,000`. The bounds match the editor and keep networked floats
away from the disabled near plane. Focused
contract8/8, storage9/9, spawn5/5, prefab runner21/21, export35 assertions
and GLua322/0 passed for that data-only boundary.

**Integrated spotlight source slice:** editor list/viewport selection,
move/rotate gizmos, numeric light settings and editor projected-light preview
are wired; explorer states that it does not preview the illumination. A
server-owned non-solid `zn_prefab_spotlight` carries anchor-transformed
position/direction and networked settings to all clients, with anchor cleanup
and atomic prop/light spawn failure. Client world lights use the bounded pool
and update at 15 Hz. Its current selection is the nearest eight *networked*
lights, not yet visibility-filtered; off-screen lights may consume the cap
or own the shadow, so the intended nearest-visible rule is not yet proven.
The engine's shared shadow-projector limit also remains a real constraint.
Fresh offline editor30/30, explorer7/7, runtime-owner9/9, spawn5/5, light
pool5/5, preview1/1 and client runtime1/1 pass; prefab runner23/23, export37,
packaging68, CSM/chest5/5 and GLua331/0 pass. GMod was launched on
`zn_preview_start` with `-disableluarefresh` verified on PID 24460. After the
user confirmed readiness, separate status showed one human, no editor and no
survivor loaded. Fresh live `zn_test_prefabs`21/21 and
`zn_test_prefab_spawn`5/5 pass. The latter creates an engine light and
verifies its transformed server state and network variables, then removes it;
it does not demonstrate client transmission. A separate request-ID-matched
client report showed zero active editor/world lights after the suite. The
pre-launch session marker was absent. Ask for the editor light visual and
interaction review; client replication, multiple clients, actual city maps,
visibility selection and performance remain open.
The user opened the editor and saved a light in their existing `test123`
prefab, but reported not noticing a shadow on the bench. Preserve that file
and the active session. Separate status confirms `gm_flatgrass`/preview,
one editor owner, no survivor loaded, and one editor projector configured
with shadows enabled and a valid 128x128 texture. That status does not prove
the shadow is rendered. The current-view capture shows a bright workspace;
the saved light and bench are plausibly in the same cone, but placement and
the intended shadow relationship still need the user's clarification and
a controlled visual comparison before changing rendering.
The user clarified that the missing effect is the bench's ground shadow;
illumination is visible. An editable drum also lacked a visible shadow.
The previously reviewed temporary `bright` probe then produced visible
ground shadows from both its server drum and at least one editable prop.
After the user matched the editor light to the probe's position, rotation,
brightness, FOV and range, the temporary projector and server prop were
removed and independently verified inactive. The user again saw no editable
ground shadow, including after changing brightness away and back to force
an update. The comparison used an unsaved temporary editor change; preserve
the user's saved `test123` and ask before discarding or reloading it. Source
now adds read-only actual-projector diagnostics to the existing client status
report; focused pool5/5, preview1/1, runtime1/1 and GLua331/0 pass. This
diagnostic source is not live-loaded. Next compare actual engine getter
values after an explicitly approved fresh same-map reload; do not assume the
cause is model drawing, projector order or light settings yet.
The user approved discarding the temporary comparison and a same-map reload.
After reopening their saved `test123`, request-ID-matched diagnostics show
the editor projector's engine getters actually return the matched warm RGB,
brightness 6, FOV 60, range 512, position `origin + (-80,-160,192)`,
angles `(40,45,0)` and shadows enabled, with 23 updates. The user saved their
comparison work; do not revert or overwrite their prefab. This confirms
settings, not visible depth shadows.
To distinguish a reference projector's shadow from its server drum's shadow,
source adds owner-only probe controls to remove just the temporary server prop
and temporarily suspend/resume the editor projector without modifying the
document. Probe stop also restores editor preview. Focused preview1/1,
client-probe1/1, server-probe2/2 and GLua331/0 pass; these comparison controls
are not live-loaded. Ask before another reload or any unsaved discard.
After the user saved and approved a reload, the comparison controls were
loaded. With the editor projector suspended and the server drum removed,
the user corrected their earlier response: the editable props did *not* show
ground shadows under the reference light. In `compare` mode, with no server
drum and the editor projector suspended, the user identified a shadow on the
southern manually drawn test drum only. Both temporary models and reference
projector were removed and editor lighting independently verified restored.
This narrows the issue but does not prove a cause: editor props also use a
`RenderMultiply` scale matrix. A new isolated `matrix` probe compares two
otherwise identical manually drawn drums, one with an identity matrix and
one without; focused client-probe1/1, server-probe2/2 and GLua331/0 pass.
The matrix probe is not live-loaded. The open editor has a temporary
unsaved range change; ask before reloading or discarding it.
After the user approved another reload, the empty-editor matrix probe showed
no shadow from either of its drums. The follow-up engine/manual comparison
initially received a "neither" response, which the user corrected: the
southern manually drawn drum did show a shadow. These cases placed the test
drums differently, so they do not establish whether the matrix affects
shadows. Both probes were stopped; separate client status verified no test
models/projector and the empty editor preview was resumed. Source now adds
owner-only commands to apply/remove an identity `RenderMultiply` matrix on
the *same* manually drawn comparison drum, with a projector refresh. Probe
client1/1, server2/2 and GLua331/0 pass; this toggle is not live-loaded.
Ask before a same-map reload, then compare the same drum before/after toggles.
After an approved reload, the user saw the southern manual comparison drum's
ground shadow both before and after applying the identity scale matrix;
the client confirmed the toggle and a second projector update. Matrix alone
is therefore not the reproduced cause. The probe was removed and preview
resumed. The user placed an editable drum at the same local `(80,-45,0)`,
rotation zero and scale one. With only the reference projector active and
its temporary server prop removed, the user saw no ground shadow from that
editable drum. The probe was stopped; the editable drum remains an unsaved
test. Source now lets the owner remove the other comparison model and apply
the editor's skin, identity matrix and render-bounds setup to the same manual
drum; status also reports the editor's authored props. Focused preview1/1,
client-probe1/1, server-probe2/2 and GLua331/0 pass. These controls need
a fresh approved reload; preserve or explicitly discard the unsaved drum.

After the user approved a reload, a clean comparison with one manually drawn
drum and no server/engine-drawn test drum showed no ground shadow, despite
earlier ambiguous multi-model observations. A follow-up comparison was
started but the user then explicitly asked to stop and defer this issue to
the end of Alpha 3.3. The probe was stopped; a separate request-ID-matched
client report confirmed both temporary models and the projector were gone
and editor preview was resumed. The session remains on `gm_flatgrass`/
preview with one owner, no survivor loaded and an empty editor document.
Do not continue or accept the shadow investigation during other phases.
The user then returned to `zn_preview_start`/preview. Separate status showed
one connected human, no editor owner and no survivor loaded; the session
marker was absent. The compact, sorted city/preview persistence sections
again hash to `114b276049cdc9e2053d359b8160c6fc6667d79adf9f5f7432d4f3f70e1223e4`,
matching the pre-editor baseline.

**Particle slice decisions:** the user chose prefab particles next, starting
with steam and a selectable library of verified effects. Support both
continuous and one-shot behavior; one-shots are explicitly triggered
individually by ID rather than firing automatically on cell load. Include
appropriate steam audio. The user explicitly chose no fixed per-client cap
on simultaneous prefab effects; surface allocation failures rather than
silently imposing one, and measure performance before broader rollout.
The installed Half-Life 2 VPK lists `particles/train_steam.pcf`,
`sound/ambient/gas/steam_loop1.wav` and `sound/ambient/gas/steam2.wav`.
Read-only inspection of the mounted PCF in memory found `steam_train` as a
candidate name; neither its in-game appearance nor lifecycle has been
verified. First use one isolated editor prototype and human visual/audio
review before wiring the authoring and world systems. Refer to mounted paths;
do not copy Valve assets into the addon. World generation remains gated.
An editor-only probe now attempts the mounted `steam_train` system with a
spatial `ambient/gas/steam_loop1.wav` sound. It owns a hidden client audio
anchor, stops particles/audio on editor close, map cleanup or a five-minute
expiry, and reports missing assets/allocation errors rather than silently
substituting. It does not save particle data or implement triggered effects.
Offline client3/3, server1/1, editor30/30, packaging68 and GLua336/0 pass.
The preview launcher was freshly reloaded with no survivor loaded; the
live probe correctly rejected a launcher start. Open an isolated editor and
verify that the client actually creates this candidate and that the user
hears and sees it before broader work. Do not equate server acknowledgement
with client creation or review.
The first live attempt reached an empty `gm_flatgrass` editor with one owner.
The client report later showed the candidate effect invalid and its sound
and anchor removed; the user was unsure whether a brief puff or audio played.
The first status request also failed to write while the effect was active:
the prototype used the nonexistent `GetName` method. Source now uses the
documented `GetEffectName`, records elapsed completion/invalidity, and does
not label observed completion an unexpected failure. Offline client4/4,
server1/1 and GLua336/0 pass. The original probe was stopped, and a separate
client report confirmed no effect, sound or audio anchor. The diagnostic
fix needs a fresh approved editor reload before testing the candidate's
actual duration; do not infer continuous behavior or visual/audio approval.
After the user approved a reload, request-ID-matched client status confirmed
that `steam_train` and the loop sound started. The effect later became
invalid at 5.68 seconds without an observed `IsFinished` state; the reason
is not yet established. On a coordinated replay the user saw the steam and
heard the sound, and approved both as a starting point for the library.
The prototype was stopped and client status confirmed no particle, sound or
audio anchor. This approves the short example, not continuous looping,
triggered world playback or lifecycle behavior.
An isolated `loop` probe now replaces the candidate after its effect handle
becomes invalid while retaining the same sound anchor and sound patch; a
failed or immediately invalid replacement reports an error and removes
owned resources. It has no simultaneous-effect cap and does not change
saved prefab data. Offline client5/5, server1/1 and GLua336/0 pass. This is
an experiment, not evidence that the effect appears or sounds continuous;
reload the editor only with the user's confirmation and review over multiple
cycles before designing world playback.
After the user approved a reload, the loop remained active with sound through
multiple effect replacements; the user confirmed that both steam and audio
looked/sounded continuous and suitable. The prototype was stopped, and a
separate client report confirmed no active effect, sound or audio anchor.
The user chose per-effect overlap controls for repeated individually triggered
bursts: overlap is on by default for new effects; when disabled, a new trigger
restarts the current burst. No fixed simultaneous-effect cap is authorized.
The continuous prototype is accepted as a starting point, not yet authoring,
world replication, Hammer input or multiplayer acceptance.
The particle data boundary now has a packaged, validated effect catalog and
optional schema-1 particle records with stable IDs, local transforms,
continuous/triggered mode and per-effect overlap (default true). Server
storage and explicit export reject unknown effects; old documents load with
no particles. Until runtime spawning is implemented, a particle-bearing
prefab fails explicitly before creating props rather than silently dropping
effects. Explorer reports that particles are not displayed there. Offline
contract9/9, storage10/10, particle catalog2/2, editor session13/13,
spawn6/6 and prefab runner26/26 pass; export42, packaging69 and GLua338/0
pass. This data-only slice has not been live-loaded and does not implement
particle authoring or triggering.
Editor particle controls are now wired in source: select a catalog effect,
add/select its handle, move/rotate it with existing gizmos or numeric fields,
switch Continuous/Triggered, toggle burst overlap and explicitly preview a
trigger. A shared client effect owner reuses the approved particle/audio
lifecycle; continuous effects update control points and sound position when
moved, triggered previews honor overlap or restart, and preview cleanup follows
document/editor/map lifetime. There is no fixed concurrent-effect cap; a
fixture exercises 40 overlapping bursts. Offline editor32/32, editor
session13/13, particle preview3/3, shared effect/probe6/6 and GLua341/0
pass. This source is not live-loaded; actual editor interaction, movement,
sound, save/reopen and rendering still need a fresh-load review. World
spawning remains explicitly blocked for particle-bearing documents.
After the user approved a fresh editor reload, `zn_test_prefabs` passed
23/23 in game with one editor owner and no survivor loaded. The user
confirmed the continuous steam/sound and movement controls, triggered
preview and overlap toggle, and save/reopen work. Their saved `teststeam`
document contains a continuous `steam` particle with stable ID and transform;
preserve it. The editor remains open. This is authoring/preview review only;
server-side world spawning and Hammer trigger delivery remain unimplemented.
World source now validates particle catalog entries before spawning,
transforms continuous emitters through the authoritative anchor and sends
individual triggered events with the authored overlap rule. A
`TriggerParticle` Hammer input accepts a particle ID; anchor/map cleanup
stops owned continuous effects and active triggered bursts. Events are
delivered to currently connected clients, not replayed to late joiners.
The client uses the same approved steam/audio owner and has no fixed cap;
offline fixtures exercise 40 concurrent continuous and triggered effects.
An owner-only synthetic editor probe is prepared to exercise a transient
networked continuous emitter plus separate overlap/restart triggers without
staging maps or modifying a survivor. Focused spawn6/6, runtime owner10/10,
world client4/4, transport1/1, anchor input1/1, probe1/1, anchor20
assertions and GLua351/0 pass; prefab runner30/30, export42 and packaging69
passed before the final test addition. The actual engine, client transport,
human review, multiplayer, city-cell and compiled Hammer input remain open.
Instance-local anchor target-name fixups also require separate verification;
do not infer trigger routing from the generated point's transform.
After the user approved a fresh editor reload, the synthetic world fixture
ran with one owner and no survivor. Request-ID-matched client status showed
one networked continuous effect, then two active bursts after two overlap
triggers and one active burst after two restart-only triggers. The first
fixture expired while awaiting visual review; status confirmed automatic
cleanup. After restart, the user confirmed server-created continuous steam
and triggered bursts were visible and audible. The fixture was stopped and
separate client status confirmed zero continuous effects, bursts and pending
entities. This proves the isolated synthetic server/client path only—not a
compiled Hammer input, an actual city cell, late join or multiplayer. The
editor remains open; return to the launcher and verify the survivor baseline
before the live launcher spawn suite.
The user returned to `zn_preview_start`/preview; separate status showed no
editor owner or loaded survivor, the session marker was absent, and stored
city/preview persistence matched the pre-editor baseline. Fresh in-game
`zn_test_prefabs`23/23 and `zn_test_prefab_spawn`6/6 pass, including native
particle entity transforms and network variables. A particle variant of the
existing hash-ledger anchor stager and a guarded fixture-only engine-input
command are prepared: staging fixtures14 assertions, runtime owner11/11
and GLua351/0 pass. The retained compiled anchor BSP passes28 assertions;
read-only staging inspection found the destinations free. No new compile or
staging has run. Ask before temporarily staging/entering this exact fixture.
The test would exercise `Entity:Fire` on a real compiled anchor, but not
prove instance-local Hammer target-name fixups, actual city or multiplayer.
The user approved that bounded staging and entry. The retained fixture was
staged with the hash ledger; separate status confirmed `zn_dev_prefab_anchor`/
preview, one owner and no survivor. Synthetic cell0 selected the temporary
prefab at five compiled anchors, producing five continuous and ten triggered
particle records. Client status reported five continuous effects; firing the
real anchor's `TriggerParticle` input twice yielded two overlapping bursts,
and two restart-only inputs yielded one. The user confirmed the steam was
visible, audible and sensibly positioned. After owner-only return to
`zn_preview_start`, client particle status was empty, the marker was absent,
and stored city/preview persistence matched the baseline. Hash-ledger
restore removed both temporary BSP copies, the prefab and ledger; each is
verified absent. This is a bounded compiled-anchor/engine-input check, not
proof of Hammer target-name fixups, actual city eligibility, multiplayer,
late-join behavior or matched performance.

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

### A3 - Prefab editor UI refinement (user-requested, accepted with limits)

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

**User decisions, 2026-10-30:** slow short-range idle wander with pauses;
120° forward cone to 800 units plus a 150-unit all-round close sense, always
with line of sight; hearing for gunshots, sprinting footsteps, melee impacts
and breaking props; a spotting walker wakes others within 400 units once,
with no chains; forget the target after 10 s and return to the spawn area,
with nothing persisting across cell loads; grouping and infighting both
enabled as exploratory toggles; ~0.5 s wind-up (live-tuned to 0.9 s), one
dodgeable hit, ~0.6 s recovery; damage stays 12 (armour/reduction belong to Phase C); mounted HL2
zombie sounds. Culling is fixed by reasoning now (camera-aware PVS, never
despawn a camera-visible walker), with live verification later and no
baseline capture first.

**Source implemented, 2026-10-30 (not live-verified):** the culling cause was
`DespawnExcess` removing unengaged walkers in ticket-key order regardless of
distance or visibility. New `gamemode/sv_walker_awareness.lua` validates
rate-limited camera reports from `cl_thirdpersoncamera.lua`, adds the camera
origin to the PVS, provides visibility, noise and one-shot alert routing,
and owns the `zombiesim_walker_grouping`/`zombiesim_walker_infighting`
convars. The materializer restarts grace for visible walkers and removes
excess unseen walkers farthest first. The Walker entity implements the
cone/close sense, investigation, alerts without chaining, wander/home
return, wind-up/hit-or-miss/recovery, cosmetic scuffles, sounds and new
status counters; the infighting shove deals no damage. GLua 378/0 and
offline Walker fixtures 10/10 (5 new behaviour, 5 existing spawning) pass.
Live checks still needed: wander, vision, hearing, alerts, a fair dodge,
sounds, scuffles, the gesture hit-frame against the 0.5 s wind-up, server
`PlayerFootstep` coverage, camera PVS and no in-view despawn.

**First live review and fixes, 2026-10-30:** the user reported lag, a walker
despawning in view, a too-short wind-up, walkers spawning in the ground or
launching into the sky, walkers stuck on props and on each other, and green
radiated glow popping in at its 1500-unit cut-off. Source fixes: wander,
investigation and last-known moves no longer recompute static paths every
1.25 s; visibility samples head/centre/feet with a 6000-unit camera range;
spawn placement snaps a hull to ground with `MASK_NPCSOLID` and checks the
camera as well as the eye; an airborne safety net (idle and chase loops,
0.25 s) returns a walker to its nearest nav point and logs `upwardLaunch`;
the wind-up is 0.9 s; a one-second no-progress check plus engine stuck
detection triggers up to six sidestep candidates, a 0.4-1.2 s yield behind
another walker (walkers stay solid, as chosen by the user), or a short hold
when packed in, keeping target and memory; radiated sheen/eyes fade in from
1500 to full strength at 900 units. Despawns are kept in a ten-entry
`recentDespawns` ring. Offline Walker fixtures 12/12 and GLua 378/0 pass.
**Live:** the user reported lag much better, no ground spawns, no in-view
despawns, no further sky launches, a wind-up that feels right and crowd/prop
movement good enough for now. Using the stationary
`zombiesim_dev_radiation_probe`, the user confirmed the radiated glow now
fades in smoothly. The user then noticed materialized walkers were no longer
radiated: 0/100 in cell 302 (radiation 0.778, expected ~39%). Cause:
`GetTicketSeed` was linear in near-sequential ticket ids and the first
Park-Miller draw is linear in its seed, so whole ticket batches rolled almost
identically (also clustering enemy picks). The seed now passes through a
murmur3 finaliser, with salt 1 for the variant stream; a 400-ticket fixture
covers rate, independence and determinism (Walker fixtures 13/13, GLua
378/0). After reload 36/100 walkers were radiated.
**Phase B accepted with limits (user, 2026-10-30):** no matched performance
measurement, sky-launch cause unproven (safety net only), hearing/alert
specifics and multiplayer unverified; damage/armour belong to Phase C. A mid-review status had 73 sidesteps and 21
yields for 145 stalls before the wider candidates and hold were added.
Still unverified live: lag measurement
beyond the user's impression, the sky-launch cause (safety net only),
hearing/alert/scuffle specifics and multiplayer.

**Speed changes implemented (2026-11-01):** the three speed requests below are in source. `sv_movement.lua` now uses walk 0.57375, run 0.65025 and sprint drain 30 (half of 60; recovery unchanged at 5.5). The Walker `DevelopmentWalkSpeed` is 41.25 (55 x 0.75), and the gore crawler fallback matches, so chase and wander both scale. The movement and inventory expectations, `docs/gdd.md` and `docs/readme.md` are updated. GLua 399/0 passes. After a fresh `-disableluarefresh` launch on the preview launcher, live movement 6/6, inventory 52/52 and enemies 14/14 pass. The user deployed and confirmed that walking, sprinting and stamina feel right. The walker speed feel review is deferred (user, 2026-11-01): the regenerated preview cell 243 has no navmesh, so walkers cannot materialise there. Do not claim walker feel acceptance. The capacity study is still pending.

**Launcher location fix (2026-11-01):** deploying the preview survivor failed with "LOCATION UNAVAILABLE". `snapshotLocation` in `sv_characters.lua` passed the saved logical `CellX/CellY` straight to the raw-grid `ZM_World:GetCell`. Negative-Y cells returned nil, and positive-Y cells silently resolved the wrong cell. It now converts with `GetGridCoordinates` first. The character fixtures use logical coordinates, including a negative-Y city case. GLua 399/0 passes. After an approved launcher reload, live characters 13/13 pass. The user confirmed the card showed the correct CITY location and deployment succeeded.

**Queued user requests (2026-11-01):**

- **Player walking:** 15% slower. The current scale is
  `Movement.WalkScale = 0.675` in `sv_movement.lua`.
- **Player sprint:** 15% slower (current `RunScale = 0.765`). Sprint should
  also last twice as long: the user chose halving the stamina drain while
  sprinting.
- **Walkers:** 25% slower than now, both chase and wander. The base is
  `DevelopmentWalkSpeed 55` × enemy min/max speed, in
  `entities/entities/zn_walker_zombie`.
- **Capacity study:** measure how many walkers can be on screen before a
  noticeable frame-rate drop, using matched workloads. Then investigate
  raising that number through culling or LOD, simpler behaviour for distant
  or unseen walkers, cheaper pathing and similar measures.
- **Order:** these follow the remaining Phase G items unless the user
  reprioritises. Update the movement, inventory and enemy test expectations in
  the same change.

- [x] Capture a matched preview baseline: profile, map/logical cell, camera,
      nav availability, population, visibility, zombie lifecycle reason and
      player position. Reproduce object disappearance separately from walker
      removal. Distinguish engine PVS/render culling, camera visibility and
      server relevance/cap/transition cleanup before selecting the owner-level
      fix. Do not change visibility or spawn caps as an unmeasured blanket fix.
      *(Waived by the user: fix by reasoning, verify live later.)*
- [x] Design bounded, server-authoritative idle/wander, slow movement,
      directional sight plus line-of-sight, hearing, limited alert propagation,
      and memory/territory behavior. Specify what persists across a cell load
      and how nav failure is handled. Grouping and zombie infighting are
      exploratory; ask before adopting them as mandatory behavior.
      *(Decided and implemented in source; nav failure ends wander or
      investigation quietly and pauses.)*
- [ ] Separate attack wind-up, one damage event and recovery. Confirm actual
      model animation timing in GMod; revalidate target, range, line of sight,
      alive/state at impact so dodging works. Cancel on death/removal/transition
      and prevent repeated damage from one swing. Add requested groan,
      footstep and attack cues without introducing unbounded sound spam.
      *(Source done; 0.9 s wind-up and dodge confirmed by the user live.)*
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

**Inventory and decisions, 2026-10-30:** 16 attributes are stored, networked,
and shown on the scoreboard. `Snipers` becomes `Rifles` one-for-one;
`Pistols` and placeholder `Explosives` start at zero. The four weapon families
are Pistols (handguns/Deagle/Magnum), MachineGuns (SMGs/LMGs), Rifles (assault
and sniper rifles plus crossbow), and Shotguns. Each family point reduces
spread/recoil by 3% and reload duration by 2%, capped at 10 effective points.
Light/Medium/Heavy armour are stat-only items with 10%/20%/35% ordinary damage
reduction, 0%/5%/12% speed penalties, and 5%/15%/30% stamina-recovery
penalties. Each Endurance point removes 5% of the speed and recovery penalties,
up to 50%; it does not change damage reduction. The Radiation Protection Suit
stays separate. No armour loot rates, job restrictions, or distinct armour art
have been approved; do not invent them. The current definitions reuse the
mounted HEV suit icon model as a placeholder.

**Implementation and validation, 2026-10-30:** the migration rebuilds legacy
rows transactionally, preserves profile/revision data, transfers Snipers only
when Rifles is absent, and initializes new attributes to zero. The live
preview database migrated three rows; a canonical pre/post SHA-256 comparison
matched exactly, and the slot probe still finds the saved preview character.
The first live static-data run exposed misplaced armour validation; the next
run exposed weapon-skill helpers nested inside `GetWeaponScales`. Both
placement defects were corrected before successful runs.

Offline SQLite migration/rollback tests pass 6/6 and GLua syntax passes
380/380. Live checks pass: static data 20/20, weapon catalog 55/55, weapon
effects 24/24, armour 4/4, movement 6/6, inventory 52/52, professions 12/12,
and character persistence 12/12. The latest inventory and weapon-effects
cases cover armour equip/persist/swap/unequip and firearm calculations at
0, 5 and 10 family points. No armour loot rates, job restrictions, or
distinct art were added. The user confirmed the scoreboard and inventory
presentation and reported that temporary heavy armour and a pistol worked
and felt fine. Server measurements confirmed the heavy-armour movement and
recovery penalties. Real survivor damage and ordinary firing/reloading were
not instrumentally verified.

The identified temporary armour, pistol and ammunition were removed. The
survivor's attributes and unarmoured movement matched the baseline; a
three-bandage stack appeared during the review and was preserved, so the
inventory is not identical to the initially empty baseline. A live pistol
sample showed 64 rounds against a nine-round instance maximum while the
saved preview infinite-ammunition toggle was enabled. The preview cheat
tops up to the engine clip maximum, consistent with that discrepancy, but
its active runtime flag was not sampled. This does not establish ordinary
reload behavior; do not change the user's cheat setting or claim a
normal-weapon reproduction.

The repeated world-map inspector `DrawPoly` error was reproduced in a focused
fixture: four star triangles referenced their next inner point before it
existed. The source now creates all points first and replaces a stale
incomplete cached shape. The earlier speculative scroll-visibility
workaround was removed. World-map star and catalog fixtures pass 4/4 and
GLua syntax passes 380/380. After an approved same-map reload, the survivor's
cell, attributes and inventory matched the pre-reload snapshot. The user
confirmed that the stars look correct while scrolling and the error does
not return.

- [x] Settle attribute names, transfer semantics, weapon families/effects,
      armour values, Endurance interaction, and Radiation Suit separation.
- [x] Validate shipped definitions, malformed family/armour data, migration
      behavior, transaction failures, movement bounds and weapon-scale
      replication without altering user records.
- [x] Wire modifiers through authoritative player, weapon, inventory,
      movement, and damage owners; formula and non-compounding movement
      regressions pass. Keep guards deferred as requested.
- [x] Run focused fixtures and GLua syntax checks; capture and verify the live
      profile baseline around migration.
- [x] Human-review scoreboard/inventory presentation.
- [x] User accepted Phase C with limits: real survivor damage, ordinary
      firing/reloading without the infinite-ammo setting and multiplayer
      remain unverified. The bounded equipped-gear review was positive.

## Phase D - Jobs and calling cards

**Profession selector source slice:** character creation now offers a
two-column job grid with distinct mounted icons, a selected-job detail panel,
placeholder backstory and all job attribute bonuses. Narrow widths stack the
detail panel; selection requires explicit continuation and preserves draft
points and the existing server validation. Offline picker7/7, missing-icon
handling and launcher Cell Health2/2 pass; GLua382/0 passes. After a
user-approved launcher reload, the actual-client presentation suite passed
23/23, including the picker and its wizard integration. City and preview
attributes, player data, inventory, stash, implants and character slots match
the pre-reload baseline; no survivor is loaded or was created. Human review
found the attribute table extending outside its detail box. Source now sizes
the box around all detail text and rows and uses the existing page scrollbar
instead of a nested scrollbar. Offline picker8/8 and GLua382/0 pass. After
the user cancelled the draft and approved a launcher reload, the fresh-client
presentation suite passed 24/24, including the detail bounds at four widths.
City and preview persistence, inventory, stash, implants and slots again match
the baseline; no survivor is loaded. The user says the revised screen looks
good, and requested more noticeable profession bonuses: Police should have
shotgun, pistol and rifle proficiency, and Army should be more rounded.
They chose a 10-point maximum for new survivors only, retained Civilian and
Capitalist's existing behavior, and requested clearer positive values. Existing
survivors retain the original bonus rules even after changing jobs. The user
delegated the other role-appropriate allocations. Some attributes do not yet
have gameplay effects. Capitalist's existing `playerLootBonuses` setting is
currently ignored by the static-data loader; keep that behavior unchanged
rather than claiming its cash bonus works.

**Profession balance source slice:** the server stores an additive per-character
bonus-ruleset version: existing rows default to legacy rules and newly created
survivors use the current rules. Both admin and paid job changes retain that
version. Bonuses remain derived, and job changes refresh stamina, equipped
weapon skills, movement and replicated state. The picker highlights positive
bonuses and notes the weapon cap and unfinished specialties. Isolated
balance/persistence fixtures pass 9/9, including legacy tables, profile
isolation, migration failure/idempotence, client snapshots and actual
weapon-skill refresh with engine fixtures. Offline picker Python tests pass
6/6 and shared picker cases 8/8; GLua382/0 and `git diff --check` pass.
After a user-approved preview-launcher reload, the additive migration left
both existing characters on legacy version 1. Sixteen survivor-related
tables match the pre-reload rows, excluding the new version column, both
immediately after migration and after the tests; a verified local SQLite
backup is retained in the session files. Fresh server suites pass: static
data20/20, professions14/14, characters13/13, mastercraft9/9, weapon
effects24/24 and movement6/6. The native profession fixtures exercise the
real server hydration and snapshot methods with fake players/networking,
not actual deployed survivors or multiplayer replication. A fresh client
report passed all profession cases but was 23/24 overall: its Home Earth
input-ownership case failed, and Home readiness was not independently
established before running it. After the camera reload below, a fresh
confirmed-Home run passes 25/25, including that Home case. The user confirmed
the revised bonus highlighting looks good without saving a survivor.

The user authored a `create_character` camera in the preview launcher and
requested it in the city launcher too, with a room to be authored later. The
city launcher source now has a matching initial marker. Server/client source
transports its pose, includes its origin in the PVS, and uses it for creation
and legacy appearance pages through pending saves; credits retain priority,
and absent or invalid markers warn and fall back to `menu_camera`. Launcher
fixtures pass 15/15, including eight camera cases; source parity checks both
markers. The user approved compiling, staging and reloading the preview
launcher. VBSP/VVIS/VRAD pass; the compiled camera matches its source and
both installed BSPs hash `BFF1D6689B9AAF7060676D87217DE0AF4CDBDB791B17361D517A39874976502E`.
The original preview BSPs are hash-backed in the session files. A separate
fresh client status received the authored camera within 0.04 units/degrees
and returned to ready Home after the 25/25 client suite. City and preview
survivor persistence match the pre-build snapshot after reload and tests; no
survivor is loaded. The user confirmed the preview creation view and
Back/Cancel navigation look good. A separate post-review status confirms
ready Home and matching city/preview persistence. Actual legacy appearance
and save-in-flight navigation remain unverified live. The user separately
approved the city launcher build, staging and temporary review. Its
VBSP/VVIS/VRAD and compiled-camera checks pass; both installed BSPs hash
`D25AB5A6F489AA8BA8FCC8419D3A49814FCC160264F0AD8B1E44B0F555A58639`,
and previous copies are hash-backed in session files. The user confirmed the
city creation view and Back/Cancel navigation look good; a fresh user-run
client status verified ready Home and the received pose within 0.04
units/degrees. After the approved return, separate server/client status
confirms ready `zn_preview_start`/preview, no survivor loaded, restored
selected profile and city/preview survivor data matching the pre-visit
snapshot. No room geometry or world-cell maps were changed.

- [x] Prototype the profession grid, selected job icon and detailed attribute
      table in the existing creation flow, with clear placeholder backstory.
      Preserve point allocation, server validation, existing character data,
      Back/cancel and mouse ownership. User reviews the UI in a running client.

### D1 - Calling-card artist pipeline and catalogue

**Goal:** artists can drop in finished PNGs or configure generated cards,
then build and stage both types through one catalogue. This is part of the
calling-card phase, not a reason to interrupt the top-priority prefab work.

**Artist decisions, 2026-10-30:** classify finished files by the
`_background.png` and `_details.png` suffixes; other PNGs are recipe
ingredients only when referenced, otherwise report them. Finished PNGs may
use any 6:1 resolution and retain their original bytes and transparency;
generated designs use 750x125. JSON recipes use explicitly named outputs
and ordered full-cover/repeating layers with colour, opacity, scale, spacing
and position controls. IDs derive from the category and source name; a
removed design retains ownership and displays the default until it returns
or an explicit rename alias is supplied. The first review may include at
most 512 generated designs, without silently dropping any; larger builds
remain separately approved. At that decision point the artist-source folder
had no PNGs. Temporary original fixture art is not approved as finished
staged content.

**New ingredient preview:** the user supplied one dirty-paper pattern and
two transparent symbols, creeper and weed. The paper is byte-identical to the
existing default background. The user confirmed that all three, including the
creeper symbol, are cleared for use and distribution; this is user-reported
permission, not independently verified licence text. They chose a small
preview with separate backgrounds and details. Three paper colour variants
and two tiled symbol layers were built in
`generated/callingcards_preview/build-a4288f7edf9a4f05b395c31dab649bd8`.
All five catalogue hashes, 750x125 dimensions, detail transparency and
unclipped sides pass. A six-combination sheet in the session files approximates
the scoreboard's 70/225 layer alpha; it is not an in-game screenshot. The
user approved the sheet for an initial in-game review, not final in-game
appearance. The user chose den-trader purchases at 5 credits per design,
future quest eligibility and no player resale. The rebuilt artwork is
byte-identical to the reviewed preview. Actual catalogue entries passed
isolated five-card purchase/reward and resale-rejection checks; expanded
catalogue fixtures pass 14/14. Plan and staging dry-run pass, artist fixtures
pass 88/88, and the user approved staging these exact five designs and the
shared catalogue. All seven installed materials and catalogue hashes match;
the staging updated the detail-default digest to the image's current digest
without modifying either default image. The user deferred survivor and artwork
review; obtain separate approval before deployment, purchases or selections.
No world generation or production world output changed.

**D1 source foundation:** `recipes.json`, isolated preview composition,
catalogue validation and guarded staging are implemented. The installed
catalogue contains the two unchanged defaults and five approved designs.
Static-data loading retains the prior registry on
validation failure, and packaging includes the catalogue and checks material
hashes. The resolver can report a missing/aliased selection and return the
default without changing its ID; ownership and selections were implemented
later in D2 below. Calling-card fixtures pass 73/73, Workshop packaging 73/73, Phase D
offline Lua/Python integration 20/20, and GLua syntax 383/0. These use
temporary fixture art and are not visual acceptance. After the user confirmed
the draft was safe and approved a preview-launcher reload, native static-data
fixtures pass 22/22, including both calling-card cases; `zn_validate_static`
reported zero errors, the existing Capitalist warning and two loaded cards at
that earlier defaults-only checkpoint.
The fresh actual-client launcher suite passes 25/25, and a separate client
status confirms visible Home. City/preview player data, attributes and slots
match the pre-reload reports; 19 survivor/related SQLite table digests match
both after reload and after the client suite. No survivor is loaded. These
checks do not establish actual calling-card material appearance. A real
handcrafted/generated scoreboard review remains open; the approved generated
artwork has since been staged. No world build or production output was changed.

- [x] Use the existing `assets/scoreboard/callingcards` as the artist-source
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
- [x] Let JSON recipes reference images in the same source area and configure
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
- [x] Document the artist workflow, supported filename conventions, recipe
      settings, dry-run/build/staging steps, ownership and recovery behavior.
      Ask before an expensive catalogue build or broad staging; this planning
      request does not itself run either.

### D2 - Calling-card ownership and scoreboard

**Decisions, 2026-10-30:** unlocks belong to the Steam account within each
world profile and are shared by its survivors in that profile. Backgrounds
and details unlock independently; only the two existing defaults are owned
automatically. Each survivor saves its own selections, which other players
see on the scoreboard. Purchases use that survivor's credits at a den trader,
not the scoreboard. Individual designs may be shop-priced, quest-only or both;
quest integration is deferred if no quest owner exists. These choices do not
approve artwork staging or imply visual, multiplayer or gameplay acceptance.

**D2 source slice:** account/profile unlocks and per-survivor selections use
server-owned storage. Deleting a survivor removes its selection, not the
account unlocks. The scoreboard pencil lists owned and locked designs; den
traders offer separately priced designs after confirmation. Credit debit,
unlock and trade-ledger entry commit atomically, and replayed requests do not
charge again. Missing designs or materials display their defaults without
rewriting saved IDs. Prices and explicit quest eligibility are validated by
the artist pipeline; `GrantReward` is server-only and quest integration remains
deferred. Request-correlated chunked responses handle stale or incomplete
client state. The shared installed catalogue contains the defaults plus the
five approved 5-credit, quest-eligible designs.

Offline Phase D fixtures pass 41/41, including an isolated SQLite execution of
the native server suite (4/4 cases), server-to-client wire serialization,
fault-injected purchase rollback, a 5-credit purchase and rejected resale,
client transport4/4, selector/shop6/6 and cached-factory bootstrap and
environment-isolation regressions.
The artist pipeline passes 88/88, Workshop packaging 73/73 and GLua syntax
390/0. After an approved preview-launcher reload, the native calling-card
suite passed 4/4 and static-data fixtures pass 22/22; after approved staging
and another launcher reload, static validation loaded seven cards with zero
errors and the already documented Capitalist warning. The native suite uses
preflighted synthetic profiles and cleans up its rows. All 21 checked table
row sets match the verified pre-reload backup after staging and the client
tests; the two new calling-card tables were absent in that backup and remain
empty. The fresh client state fixtures passed4/4, but the client UI fixtures
failed0/6 because their deferred module loader returned nil. Source now caches
the initializer during bootstrap and restores its environment on success or
fixture error; offline tests cover deferred loading and production UI
isolation. After a user-approved launcher reload, fresh client reports pass
state4/4 and UI6/6; all 21 checked database row sets still match the verified
backup and both new calling-card tables remain empty. A separate status confirms
`zn_preview_start`/preview, one human, no editor participant and no loaded
survivor, and a fresh client report shows ready Home.
Real scoreboard/trader interaction, actual purchases, handcrafted/generated
presentation, multiplayer and phase acceptance remain open. The user deferred
survivor/artwork review; obtain consent before another reload or deployment.

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

**Deferred (user, 2026-10-31):** the dancer head-tracking work is deferred
until later; do not resume it without a new request.

The user confirmed the supplied credits track is cleared for inclusion and
redistribution; this is user confirmation, not independently verified licence
text. Its source is 3,951,932 bytes, approximately 225.245 seconds, and SHA-256
`150A7F4057809ED6257748783AFA406B796E9A2966156E6260CC5DBB83A0B082`.
The source implementation pauses and resumes the launcher track, owns and
fades the credits channel, honors the existing music toggle and
`snd_musicvolume`, and includes the canonical sound in common packaging.
Focused audio lifecycle11/11, isolated packaging74/74 and GLua391/0 pass.
These fixtures do not establish that the music is audible in the game.

The four named dancers are mounted-model ragdolls. A preview-admin, read-only
client probe records each head and parent bone, head physics-bone ID, eyes
attachment, actual credits-camera view and music channel; it refreshes bone
caches but does not move the entities or change their physics. Focused
probe6/6 covers access, missing/non-finite data and client/bridge wiring.
After a user-approved preview-launcher reload, a fresh client report confirms
the probe is loaded and correctly reports inactive credits. The launcher is
at Home with one human and no loaded survivor; 19 existing database table row
sets match the verified backup and the two new calling-card tables are empty.
The user opened Credits and confirmed the song was audible. A later client
snapshot found Credits inactive, so it did not measure any dancers; do not
infer why the view had changed or treat the later snapshot as evidence against
the user's audio observation. The user deferred another dancer snapshot; do
not retry without agreement. Inspect the four models before choosing
head-tracking axes. Actual head motion, music volume/exit paths, both profiles
and D3 acceptance remain unverified.

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

**Launcher Play transition redesign (2026-11-01).** The user removed the
city diorama. Pressing Play now fades to black and fades in at the authored
`deploy_camera`; Back fades through black to the Earth. The black overlay
draws in `DrawOverlay`, above VGUI, with smoothstep easing. The approved
timing is 0.22 s out, 0.1 s black and 0.4 s in. Launcher panels fade with
the darkness, then wait 0.1 s after the new scene appears and fade in over
0.35 s. Page content is rebuilt only once the scene has swapped behind
black (`IsPresentationSwapPending`), so the previous menu no longer flashes
on Back. The card portrait `DModelPanel` ignores its parent's alpha, so it
applies the fade through its own colour. The day/night sky now swaps with
the scene while the screen is fully black, not on the next presentation
draw pass, which removed an intermittent day/space flicker.
Both launcher BSPs were recompiled and staged: preview
`6EB5D3A01BDAAA74890CD8F31BD6041896B012B2184B183FA8B7B8CCBBCDE16F`,
city `D5A52F1C843570C2F1770A9027562D3FFF64B63AB086D79DBA961906B73A904D`.
The parity test now checks the globe at `96 0 112` and the `deploy_camera`.
After approved reloads, the launcher client suite passes 24/24 with no Lua
errors. The user approved the timing and panel reveal and confirmed that the
sky changes only behind black (user review, 2026-11-01). `buildcubemaps`
has not been run on the new launcher BSPs; it is a manual user step. The
city launcher has not been reviewed live.

## Phase E - Player structures and claims

**Moved to [Alpha 3.4](todo-alpha-3.4.md) on 2026-11-02** (user): Alpha 3.4
continues the unfinished Alpha 3.3 work. See its Phase E section.

## Phase F - Asset staging and targeted refactors

**Moved to [Alpha 3.4](todo-alpha-3.4.md) on 2026-11-02** (user): Alpha 3.4
continues the unfinished Alpha 3.3 work. See its Phase F section.

## Phase G - Better fog (least-priority presentation work)

**Revised direction (user, 2026-10-30):** rethink fog in both the skybox and
the level. Source distance fog should no longer be the primary fog: it
overcasts the whole 3D skybox so only silhouettes remain, and the skybox
should now be optimized for visible detail. Lower Source fog overall and
apply it only very lightly in the skybox, always to both buildings and the
skyscraper silhouettes, keeping it configurable. The main fog must be new
volumetric fog (for example, a dim layer that skyscrapers rise out of), not
an overcast. Particles, sprites or other available Source effects are
candidate techniques; the exact system is still to be designed. This
supersedes the
"simplest Source fog adjustment first" item below.

**Further direction (user, 2026-11-01):** the current fog is broken and is
being rethought, not tuned. Fog should mainly communicate weather and
radiated zones. Replace default Source fog as the main effect with a custom
system; Source fog may still be applied extremely gently where it helps. The
new fog must (1) improve skybox visual density and clarity and (2) make the
level seem larger than it is. Radiation is per cell (`cell.radiation` 0..1
through `ZM_World:GetRadiationIntensity`), so radiated neighbour cells in
the skybox can be shown as well as the current cell.

**Phase G decisions (user, 2026-11-01):** layered design. A gentle matching
base Source fog for world and skybox; a skybox ground-fog layer that
skyscrapers rise out of, with aerial-perspective fading; in-world edge haze
and ground mist to make the level seem larger; weather-driven density; and
radiated zones shown as a sickly yellow-green haze, in the current cell and
over radiated skybox neighbours. Prototype order: base fog plus the skybox
ground-fog layer first, with visual review before each next step. The Low
quality preset keeps a cheap simplified layer rather than turning it off.
Added to Phase G scope at the user's request:
- clouds that are more noticeable and visibly move;
- lightning strikes;
- rain reworked so it also appears around building edges, not only over the
  player's head;
- split `cl_skybox.lua` into a module system like the atmosphere modules,
  with profile-driven size and local-scope complexity.
New skybox fog work starts as a separate module; a full skybox split must
preserve current behaviour and is a separate step.

**First prototype (source-only, 2026-11-01; not live-loaded):**
`gamemode/skybox/cl_haze.lua` draws a static nested-shell skybox ground-haze
`IMesh` (high 8x48, Low 4x24, off at `zombiesim_sky_haze 0`), rebuilt only
when cell/profile/radius/tier change. Shell alpha accumulates exponentially
toward the horizon, radiated neighbour columns are tinted yellow-green, and
weather eases density/height. `cl_skybox.lua` draws it after activity and
before clouds, with a `zombiesim_sky_haze_density` tuning slider and status
diagnostics. `zombiesim_fog_style` (default `layered`, alternative `legacy`)
pushes Source fog out (start x1.4, end x1.6, density x0.45), tints it toward
yellow-green by player radiation and halves the skybox fog amount; `legacy`
keeps the original values exactly. Offline atmosphere19/19 (new layered/
radiation/legacy case) and GLua392/0 pass. No haze offline fixture yet.
Layered density <1 disables snow fog-culling (possible cost). Visual
appearance, dome/tower-fog interaction, density factors and performance
are unreviewed.
After a user-approved reload of `zz_preview_8577eb587cd3-oceanw`, the user
reported the skybox ground haze looks good and the scoreboard bio pencil is
correctly placed and opens the editor. Weather/radiated-cell variants, the
Low preset, legacy comparison and performance remain unsampled.

**In-world edge haze and ground mist (source-only, 2026-11-01; not
live-loaded):** `gamemode/atmosphere/cl_world_haze.lua` (`Modules.WorldHaze`)
draws static per-side curtain `IMesh`es in the traversable-to-seam band
(2240..2880 in preview; high 3 curtains x32 columns, Low 2x16, off at
`zombiesim_world_haze 0`, preset Low0.5/Medium/High1), rebuilt only on
tier/bounds change. Each side fades out as the player approaches it
(300..1200 units). Pooled camera-facing ground-mist sprites (high48, Low16)
seed at most two per frame on open-sky walkable ground within the visual
bounds. Density eases with rain/snow/storm and player radiation, and colour
follows the layered fog tint. It is disabled for `legacy` fog style, dens,
the launcher, prefab editor and map captures, and skips depth/skybox passes.
`zombiesim_world_haze_density` is a tuning convar; diagnostics expose a
`worldHaze` snapshot. Offline atmosphere24/24 (five new world-haze cases)
and GLua393/0 pass. Seam hiding, sense of scale, mist appearance, weather/
radiated variants, the Low preset and performance are unreviewed.

**First live review and radiated tuning (2026-11-01; source/offline only):**
the world haze was live-loaded on `zz_preview_d5f99e3edc66`; the user found
the edges too weak, the mist too faint, atmosphere changes popping, and wanted
radiated cells to feel post-nuclear. Choices: heavy yellow-green fog closing
in, falling fallout ash, a darker brown-orange sky, a distant fiery horizon
glow and stronger ground dust; yellow-green near the ground, orange in the
sky. Source now: layered fog eases all targets with a 3 s time constant
(snapping on first use/profile or style change) and adds an eased radiation
fog (start x0.65, finish x0.5, density toward0.85, colour {150,165,55}) plus
a separate darker orange `skyColor` consumed by the skybox fog; skybox haze
thickens/rises with eased radiation and a static additive horizon glow ring
draws behind towers in radiated cells; world haze is stronger (curtains
1200 high, stack opacity0.82, mist64/20 larger sprites, eased density) with
a dust tint and a pooled fallout-ash layer (high160/Low60, scaled by
radiation, open-sky seeding, one batch). Legacy fog is unchanged. Offline
atmosphere24/24 (updated cases cover easing, radiated fog/sky colour, ash
seeding/draw/fade) and GLua393/0 pass; the skybox glow has no offline
fixture. Live appearance, weather smoothing, the Low preset and performance
are unreviewed.

**Top-down fog fade (2026-11-01; source/offline only):** the user asked for
fog to fade away in the top-down camera. The locked top-down camera exposes
`ZM_GetTopDownCameraWeight()` (smoothstepped lock glide, zero in the den
camera); layered Source fog density and world-haze curtains/mist scale by
`1 - weight`, so they ease out with the camera glide and return in the free/
shoulder camera. Fog range, colour, skybox haze/glow and fallout ash are
unchanged, and legacy fog is never faded. Atmosphere25/25 and GLua393/0 pass.
The radiated tuning was reloaded on `zz_preview_49d203952b23-v1` before this
change; after a second approved reload the live client reported topDown1 with
haze alpha0, and the user confirmed the top-down fade and the free/shoulder
fog and haze look right. Radiated review: otherwise fine but too green, so the
fog's yellow-green weight drops from0.75 to0.35. After a reload on
`zz_preview_1c3546b3ae49` the user found the green too hazy against the red
sky and asked for red matching the sky, slightly less haze, and fire embers.
Radiated fog now leans0.7 toward the sky's burnt orange (170,92,40); radiated
density0.7, start/finish scales0.25/0.35, world-haze radiation boost0.5 and
red-brown mist dust. Additive `sprites/light_glow02` embers (low12/high36)
rise and swirl in open air with radiation, like the ash, and stay visible in
top-down. Atmosphere25/25 and GLua393/0 pass. After an approved reload the
live client reported radiation1,160 ash and36 drawn embers with no material
error; the user approved the red-orange fog and the embers.

Operation sample, 2026-11-01. This is operation evidence only, not a matched
comparison.

- **Setup:** map `zz_preview_a39fe92b1e79-v3`, logical cell (14,-1), clear
  weather, radiation0.667, world-haze tier High, free camera. The user stood
  still with the game in the foreground; other quality settings were not
  captured.
- **Whole frame (10 s client hook profile):** average 38.8FPS, p50 17.0ms,
  p95 45.6ms, Lua hooks 5.89ms per frame.
- **Skybox draw:** 3.07ms per frame and 98KiB per frame. This is the largest
  owner and predates the haze work.
- **World haze:** draw 0.443ms plus think 0.179ms. The status read 107 ash,
  24 embers, 3 curtains and 64 mist particles.
- **Other hooks:** skybox fog 0.069ms; colour correction 0.053ms.

The hook timings exclude engine particle and sprite fill cost.

**Low preset, same cell:** the user set the Low preset and judged that the
fog, ash, embers and skybox look right. The sample used the same 10 s method.

- **Setup:** tier Low; the status read 40 ash, 8 embers, 2 curtains and
  20 mist particles.
- **Whole frame:** 56.9FPS, p50 16.6ms, p95 19.3ms, Lua hooks 3.87ms per
  frame.
- **World haze:** draw 0.221ms plus think 0.090ms.
- **Skybox draw:** 1.97ms per frame and 195KiB per frame.

The preset changes many other settings and the view was not controlled, so
these figures do not attribute the FPS difference to the haze. A matched
non-radiated comparison remains open.

**Moving clouds (2026-11-01):** the deck in `cl_skybox.lua` was rebuilt to be
more visible and to move.

- **Drift:** about 4× faster at 7 sky units/s, rising to 2.5× in storms. Drift
  is integrated per frame, so speed changes never jump the deck.
- **Clusters:** 72 instead of 56, with larger puffs.
- **Cover and opacity:** clear-weather cover rose from 0.38 to 0.55, and
  opacity rose.
- **Billowing:** each puff slowly spins in place.
- **Diagnostics:** status now reports `cloudSpeed`.

The Low preset still turns clouds off. GLua393/0 and atmosphere25/25 pass.
After an approved reload (`zz_preview_900219675ce7`, 22 clusters, cover 0.55)
the user said the clouds look great.

**Lightning (2026-11-01):** a new module, `gamemode/skybox/cl_lightning.lua`, is
included by `cl_skybox.lua`. Lightning is cosmetic and client-local. It
strikes only in rain with storm intensity ≥ 0.3, every random(20,60)/storm
seconds, so about 36–109 s at normal rain. It does not strike in the launcher
or a den.

- **Bolt:** a branching 3D-skybox bolt with a cloud-base glow.
- **Flash:** 1–3 pulses that brighten the sky and cloud fog colour. A gentle
  world `DrawColorModify` flash is halved under shelter.
- **Thunder:** mounted `ambient/atmosphere/thunder1-4.wav`, delayed by
  distance (0.4–6 s).
- **Reduced mode:** the `zombiesim_lightning_reduce_flashes` option (under
  Advanced sky & horizon) gives a single pulse with a much softer flash.
- **Dev command:** `zombiesim_dev_lightning_strike` (bridge) forces a strike.

GLua394/0 and atmosphere25/25 pass. After an approved reload on
`zz_preview_8577eb587cd3-oceanw`, logical (0,0), in rain at storm 0.55, the
status confirmed the strikes, bolt draws, played thunder and loaded
materials. The user approved the bolt, sky flash, world flash and thunder.
The user skipped the live check of reduced mode, so it is unverified. The user
chose to leave the option where it is: a future first-run photosensitivity
prompt will disable lightning flashes and any later flashing effects. That
prompt is deferred and not yet designed.

**Reported (user, 2026-11-01): fog z-fighting.** When fog overlaps a solid
in the skybox or level at just the right angle, it z-fights; the user
suggested making the fog layer flutter. Not yet reproduced. All haze layers
are translucent, depth-tested and do not write depth. Candidate causes:
camera-facing mist sprites swinging near-parallel to a nearby wall, and
static curtains/skybox shells cutting through solids. Isolate which layer it
is (`zombiesim_world_haze 0` / `zombiesim_sky_haze 0`) before changing it.
The user placed it at the haze wall at their cell's edge: a flickering,
striped patch. Hypothesis: the edge curtains were straight, axis-aligned
planes on the 16-unit grid (e.g. 2368/2592/2816), so one could lie in the
plane of an authored wall face. Source fix: curtains now zigzag in small
pleats (20 units, +5.5 off-grid base), so every segment is slanted by at
least 16 units and none can be coplanar with a brush face. A per-frame
flutter was rejected because it would only turn the stripes into flicker.
The fixture checks that no segment is axis-aligned; atmosphere25/25 and
GLua394/0 pass. The user then reported the fix solved the issue (user
confirmation, 2026-11-01); the coplanar cause remains a plausible, not
isolated, explanation.

**Rain rework (user-selected scope, 2026-11-01).** The user chose four
problems to address: rain should stay visible while sheltered, spawn only
under open sky, run off roof edges, and reach further.
Source in `atmosphere/cl_weather.lua`:
- Precipitation no longer stops under cover. Each column is traced upward
  and spawns only beneath open sky, below that hit. Covered columns are
  rejected and counted.
- Sheltered rain sound fades to a lower volume instead of stopping.
- Rain adds a fainter far band in a forward ±62° cone at 720–1700 units.
- Up to ten roof edges are probed at a bounded rate. An edge must be open,
  with no wall between the shelter and the opening, and it emits short
  colliding drip streaks. Edges expire with time or distance and are
  cleared when rain stops or turns to snow.
- Snow uses the same sky-only spawning but has no far band or runoff.
- Boundary mist still stops under cover (unchanged).

New fixtures cover sky-only spawning while sheltered for rain and snow, the
far band, the sheltered sound, runoff at an open roof edge, rejection of a
walled room, cleanup, and a sky beyond trace range. Atmosphere27/27 and
GLua394/0 pass.
The first live load on `zz_preview_87675eafec47-v2` failed. The sky there is beyond
the 4096-unit trace, and spawning rejected any column that did not hit sky.
Spawning and the runoff probe now treat a trace that hits nothing as open
sky, as the shelter check already did; a fixture covers this. After a
second approved reload, in cell (3,-1) with rain at storm 0.55, the status
showed near and far spawns. The user approved open-ground and far rain,
sheltered visuals and sound, roof-edge drips, and said performance is fine
(user review, 2026-11-01). Afterwards the weather schedule resumed (`auto`),
and a status check reported clear weather. Multiplayer and matched
performance samples were not run.

**Skybox module split (2026-11-01).** `cl_skybox.lua` (about 2,350 lines)
now keeps the constants, materials, noise/water textures, manifest refresh,
lighting, tower drawing, hooks and commands (about 920 lines). Five sections
moved without behaviour changes into factory modules under
`gamemode/skybox/`, following the existing haze and lightning pattern
(`return function(Skybox, helpers)`): `cl_coast.lua`, `cl_edge_terrain.lua`,
`cl_clouds.lua`, `cl_activity.lua` (fires, smoke, tracers, details) and
`cl_diagnostics.lua` (`GetDiagnosticSnapshot`). The core passes one shared
`moduleHelpers` table. Coast exports its mesh helpers to edge terrain. All
modules load before the hooks and the hot-reload cleanup. `init.lua` sends
them with `AddCSLuaFile`. Checks: every free local resolves, no lines were
lost, GLua399/0 and atmosphere27/27. A temporary LuaJIT load-time comparison
showed identical method, hook, command, convar and haze/lightning surfaces
(40/7/4/8/25). After an approved reload of `zz_preview_49d203952b23-v1`,
the fresh `zombiesim_dev_skybox_edges` passed with 0 failures. The user
confirmed the skybox looked unchanged with no errors (user review,
2026-11-01).

**Noted for later (user, 2026-11-01): billboard z-fighting.** The user also
sees z-fighting on billboards. Investigate later; not yet reproduced.

**Noted for later (user, 2026-11-01): epicenter cell look.** The epicenter
uses the settlement cell. The user believes this stops the radiated
border/edge pieces from being selected, so the epicenter looks like a
residential block rather than radioactive and destroyed. **Cause verified
(2026-11-01):** settlement is only a tag. The epicenter (14,14) and the 20
other blast-core cells (x12-16, y12-16) resolve to environment profile
`destroyed`, which is first in `profilePriority`. Border and outer-edge
selection key on that profile, but only radioactive/military/fortified had
pools, so all 21 cells fell back to the ordinary walls. Source fix:
`generator-settings.json` gives `destroyed` the radioactive border and
outer-edge pools. `test_outer_edges.ps1` now asserts that parity. Its stale
1a prop count (3) and 1a-15a ocean-pool expectations were aligned with the
authored sources. The settings assertions pass. The suite's later fixture
planner calls still predate the required `-TrustedMotorwayPlan` (a
pre-existing harness gap). Also observed: radioactive cells placed mostly
`tile_industrial_3aaa` (626 versus about 18 `_ra_` placements), and there is
no radioactive terrain tile.

The user chose to prefer `_ra_` buildings wherever one fits the density
tier, keeping industrial as the fallback; they will author medium/high
`_ra_` tiles later. `Select-ZMSceneryTemplate` takes an optional preferred
pattern, and radioactive cells pass the `radioactiveBuildings` pattern. Only
`building_ra_1a` (low tier) currently qualifies. Scenery density2733/2733
passes with a new preference regression. Frontage and multi-tile now pass
when run with an isolated outer-edge settings copy and the trusted plan
(`-SettingsPath`/`-CitySettingsPath` and `-TrustedMotorwayPlan` are new
optional test parameters). The multi-tile helper now counts bus, driveway
and parking markers as junctions, matching the planner. An unmatched
full-plan comparison raises radioactive/destroyed `_ra_` building
placements from 48 to 159, while industrial still dominates (1068).
The user approved regenerating after the Cell Health batch. The change
alters roughly all radioactive-cell recipes, not just the 21 `dx` ones;
regenerate, recompile the affected maps and stage only after the batch.

**On-ramp road approach regression (user, 2026-11-01):** the ordinary road
no longer joined the motorway on-ramp in on-ramp/motorway-corner cells.
`Set-ZMTrustedMotorwayGridContract` (`bin/motorway_grid_placements.psm1`)
discarded the trusted plan's `ordinaryRoadApproaches` doglegs and replaced
them with a plain grid branch. It now restores each trusted dogleg from
native corner/768-straight/corner pieces; restored directions get no
competing grid branch. Only two trusted cells use doglegs: logical (13,18),
heading S, and (6,23), heading E. The user chose to extend (6,23) with one
extra native 640 straight so its road stays on the y=0 grid; that cell is
`grid_normalised_dogleg_hammer_review_pending`. An isolated full plan with
the Phase J inputs matched a pre-fix baseline plan exactly in every cell
except those two. Its 332 VMFs built, and both cells emit the expected
instances. `test_motorway_grid_placements.ps1` passes 1515 assertions with
the new `-BaselinePlanData` comparison. The Alpha 3.3 inputs also restore
both approaches. Not yet compiled, Hammer-reviewed or played; both maps join
the post-batch regeneration. Known pre-existing issue:
`build_motorway_cell_preview.ps1 -NormalComplex` fails because it compares
`topology` on manifest cells, which have no such field.

- [ ] Reproduce skybox mismatch and double-fog seam on the exact preview map,
      weather, camera and settings, comparing world/skybox fog ownership and
      a known-good baseline. Check sky inspection, map capture and weather
      restoration separately. Consult engine documentation before relying on
      any unfamiliar fog or rendering behavior.
- [ ] Design and prototype an isolated volumetric fog for the level and
      skybox (technique open: particles, sprites or other Source effects),
      with reduced, configurable light Source fog applied
      consistently to buildings and skyscraper silhouettes; keep distant
      detail visible. Do not modify approved materials/lighting without
      evidence and agreement.
- [ ] Compare seam, appearance and matched performance with fog isolated;
      obtain the user's visual approval before rollout. Preserve native/default,
      capture and CSM behavior and document technical limits.

## Phase H - World-generation rules and separately approved output batch (last)

**Moved to [Alpha 3.4](todo-alpha-3.4.md) on 2026-11-02** (user): Alpha 3.4
continues the unfinished Alpha 3.3 work. See its Phase H section.

## Phase I - Deferred closure and acceptance

**Moved to [Alpha 3.4](todo-alpha-3.4.md) on 2026-11-02** (user): Alpha 3.4
continues the unfinished Alpha 3.3 work. See its Phase I section.

## Phase J - World viewer, new tiles and generation changes (from former Alpha 3.4)

**Merged into Alpha 3.3 on 2026-11-02** (user): the former Alpha 3.4 viewer,
new-tile and generation-change work closes out Alpha 3.3. Unfinished Alpha 3.3
phases (structures, asset staging/refactors, world-generation output and
closure) moved to [Alpha 3.4](todo-alpha-3.4.md). Text below is preserved
from the former tracker; its "Alpha 3.4" wording refers to this phase.

**Status (user, 2026-11-01): Alpha 3.4 is now the primary focus; the remaining
Alpha 3.3 work is deferred.** Scope for this step: wire every new, improved
and renamed tile into the generator, generate fresh isolated preview data
(manifest, plan, layouts, VMFs), build the viewer and load that data into it
for review. The Satellite image is deferred until the preview world is
rebuilt. Compiling, staging, navmesh and Cell Health work need separate
approval.

#### New-tile wiring (2026-11-01)

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

### World Visualization Tool

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

#### Compile-fidelity contract (proposal, 2026-11-01, not yet approved)

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

### Generation changes (after the visualization tool)

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

#### New radiation tiles (2026-11-02)

The user added `buildings/tile_ra_building_2aaa` and `_3aaa` and
`edges/tile_edge_ra_wall_4aaa`. The buildings already match the
`radioactiveBuildings` pattern; the edge wall was added after `4aa` in the
radioactive and destroyed `wallVariationTemplates` (root and isolated
preview settings). The isolated `generated/preview_alpha34_v2` plan and three
infill passes were regenerated (all exit 0): 412 required recipes (was 394),
0 missing VMFs, 53 existing VMFs changed. Placements: `2aaa` in 83 VMFs,
`3aaa` in 92 and edge wall `4aaa` in 152. Viewer stats load 576 cells with 0
missing recipes/files; scenery density 3212, outer edges 1753, bridge
ownership 99 and motorway infill scope 1005 assertions pass. Not compiled
or staged.


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
