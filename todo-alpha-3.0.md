# Alpha 3.0 — Proposed Implementation Plan

Status: **ACTIVE** (authorized by the user on 2026-10-04).
Current phase: **Phase G — Radiation-Responsive Zombies And Gore**.

Alpha 3.0 develops the city-world presentation and the survival, interaction, and economy loops. Advanced zombie sensory behavior, animation, combat balance, and broader Romero-style tuning were explicitly deferred to Alpha 3 in [docs/alpha_2_plan.md](docs/alpha_2_plan.md).

Alpha 2.9.2 is complete and accepted in [docs/todo-alpha-2.9.2.md](docs/todo-alpha-2.9.2.md). Its full-cover snow baseline was 107.0 FPS, 9.56/12.55 ms p50/p95, 1.281 ms/frame across wrapped Lua hooks, and 61 KB/frame of Lua allocation. Compare future client-rendering work against a matched profile/cell/weather/run condition rather than treating this historical reading as a directly comparable current measurement.

## Milestone Rules

- Run phases in order. Each phase gets focused static/automated checks as its changes land, followed by the relevant live and visual checks. Fix failures before moving on.
- Record static/test results separately from live/visual results. A phase is accepted only after the user confirms its live acceptance items; do not treat implementation or passing tests as acceptance.
- Keep world-generation work in the isolated `preview` profile. Inspect the current source diff and matching plan before regenerating anything: user-edited templates are source inputs, generated artifacts are not hand-edited, and a rebuild must target only affected recipes unless a deliberate full build is approved.
- Use the repository's existing service owners, `ZM_World`, `ZM_SafeZones`, `ZM_StaticData`, `ZM_TestHarness`, and `ZM_Loading` rather than creating competing implementations.
- Do not combine unrelated high-risk changes merely to reduce test cycles. Each phase should leave the game in a recoverable, testable state.

## Phase 0 — Scope, Baselines, And Decisions

Status: **COMPLETE for Alpha 3.0 activation** (2026-10-04). Alpha 2.9.2 closure and its performance evidence are recorded above. Current user-edited data/audio files were left untouched; no authored VMF or Lua changes were present in the worktree at activation. Resolve each feature-specific behavior decision before its dependent phase, as listed under Open Decisions.

1. Close or explicitly defer any remaining Alpha 2.9.2 acceptance items before activating this tracker.
2. Inventory current user-edited VMF/VMX and Lua changes before touching or rebuilding their outputs. In particular, confirm which authored templates changed, which removed templates are still referenced, and which planned recipes they affect.
3. Record current preview build/profile, map-generation seed, service and gameplay test results, client performance baseline, and the current appearance/behavior of the listed UI and effects.
4. Agree the behavior contracts below before implementing their dependent features:
   - Dropped-item persistence, ownership/pickup rules, lifetime, stack limits, and what happens when an item cannot be placed or picked up.
   - Whether the bank's recent transactions are persisted and how much history is shown.
   - Radiation display units and the relationship between cell radiation and radiation emitted by nearby zombies. Do not label a game intensity as real sieverts/rem without a defined dose model.
   - The allowed variation around music's roughly ten-minute idle interval; playback is environment-driven, not event-reactive, and an interrupted track resumes at its saved position after a map change.
   - Which skybox elements are required for the first release versus optional weather, cloud, and snow rendering.
   - Numerical targets for foliage density, terrain/open-tile reduction, movement changes, and acceptable frame-time cost.

**Exit:** Alpha 2.9.2 is closed, the available baseline and current worktree boundary are recorded, and decisions are scheduled before their dependent features. No broad preview regeneration is part of this phase.

## Phase A — Protect Player Items And Interaction Outcomes

Status: **ACCEPTED by user (2026-10-04)**.

1. Fix safe-den stash interaction so pressing E opens a separate **DEN + INVENTORY** window showing the backpack and stash side by side. The regular inventory remains backpack-only, including when used inside a den.
2. Make profession deliveries retry safely when the inventory is full. Items must not be lost, partially duplicated, or delivered repeatedly; retry the pending delivery on a later den visit after capacity is available.
3. Keep generated ragdolls, trash, loot, and other collectible placements out of inaccessible map borders and other invalid positions.
4. Prevent an enemy's loot interaction from accidentally activating a nearby transition gate. Preserve the loot opportunity if the enemy is near a border or gate; do not delete loot merely because the player changed cells.

**Checks:** Extend the focused stash, profession, loot, and enemy suites with full-inventory/retry, boundary placement, and gate-adjacent interaction cases. Exercise retries and duplicate delivery attempts, disconnects, map changes, and full storage; prove the same item is never lost or granted twice. Run GLua syntax checks and exercise the den, delivery, loot, and transition flows live.

**Exit:** No tested item is silently lost, duplicated, or made inaccessible; gate interaction cannot steal a loot interaction.

**Progress (2026-10-04):**

- The user reported that stash use opened only the backpack. The intended behavior is a separate **DEN + INVENTORY** window; the regular inventory must remain backpack-only even in a den. The stash entity now opens the dedicated window, which presents side-by-side **BACKPACK** and **SAFE DEN STASH** columns and supports existing drag/drop and server-validated move actions. Right-click stash-move options are limited to this dedicated window. Added a server regression for stash access being limited to the current den map. Static validation passes; the user confirmed the separate-window presentation, while drag/drop was not separately tested.
- Profession claims already use an atomic inventory/claim mutation and leave full-capacity deliveries unclaimed. Extended the capacity regression to free space, retry that day's deterministic delivery, and reject a duplicate. Live retry/disconnect testing remains.
- Fallen-body placement already uses a 256-unit world-edge margin. Added a deterministic bounds assertion. Ambient debris is client-local cosmetic and non-harvestable; authored VMF trash/loot still needs review in the affected preview layouts rather than a speculative global placement change.
- Gate travel now yields when the player's aim explicitly selects a searchable loot spot, while a merely nearby fallback spot does not suppress travel. Added gate-priority and targeting regressions.
- Static validation: `.\bin\test_glua_syntax.ps1` passed (145/145); editor diagnostics report no errors; `git diff --check` passed.
- Live validation (2026-10-04): launched `.\bin\start_zombiesim_dev.ps1 -WorldProfile preview`, confirmed fresh bridge heartbeat and `zn_preview_start`, reloaded the launcher after editing, then reran the focused suites through the bridge:
  - `zn_test_inventory`: 38 passed, 0 failed.
  - `zn_test_professions`: 12 passed, 0 failed, including full-capacity refusal, same-day retry after freeing capacity, and duplicate refusal.
  - `zn_test_loot_spots`: 15 passed, 0 failed, including deterministic fallen-body map-edge bounds and aimed-vs-nearby target selection.
  - `zn_test_safezones`: 27 passed, 0 failed, including a gate yielding to an explicitly aimed searchable corpse.
- The tests ran at the launcher and establish service contracts, not visual/live interaction acceptance. The user visually confirmed that ordinary inventory shows only the backpack and using the stash opens a separate den-plus-inventory window, then accepted Phase A. Stash drag/drop and the city gate/corpse interaction were not separately live-verified; do not report them as directly tested.
- Stash UI static validation: `.\bin\test_glua_syntax.ps1` passed (145/145); editor diagnostics report no errors. The active den `zz_preview_den` was reloaded through the bridge and the server resumed ticking on that map. The user confirmed the separate-window presentation in the running client.

## Phase B — NPC Interaction And Service Navigation

Status: **ACCEPTED by user (2026-10-04)**.

1. Improve the service screen's identity/context panel: show the selected NPC's level and relevant NPC/service information rather than presenting the player's own stats as if they belonged to the NPC.
2. When an NPC offers a service, select that service by default on interaction.
3. Add the NPC hover presentation: name at the crosshair and a clear “Hold or Press E to interact” prompt.
4. Add a hold-E radial menu for the selected NPC's available services, trade, talk, and future actions. Keep the existing press-E interaction usable.
5. Establish one consistent target-selection and input/focus contract for the hover, press, hold, radial, and service-panel states. Closing the radial or service UI must restore movement, camera, and cursor ownership correctly.

**Checks:** Test NPCs with one and multiple services, no service, and unavailable actions; test tap versus hold, cancellation, distance/line-of-sight changes, and all close paths in a running client.

**Exit:** Interactions are discoverable, correct by default, and do not leave input or camera focus stuck.

**Progress (2026-10-04):**

- The Services screen now labels the player's profile as **YOUR SURVIVOR** and separately identifies the selected provider by name, role, profession, level, available services, and the selected den service's fixed fee.
- Opening Services from a service-only NPC selects that exact NPC and defaults to its first configured service. Opening Services from a combined trader/professional uses that trader's NPC identity instead of an arbitrary nearby provider; choosing a specific service from the hold radial carries that service into the screen.
- Den NPC hover presentation and a tap-versus-hold E controller are implemented. Tap reuses the NPC's existing open behavior; holding opens service/trade/talk radial choices plus a disabled **COMING SOON** segment. The Talk action opens a factual NPC information panel rather than implying dialogue content exists.
- Target selection and server validation share a 160-unit interaction radius and line-of-sight check; custom tap interactions additionally require the server eye trace to hit the selected NPC. Radial focus registers with `ZM_UI` so removal/cancellation restores cursor ownership, and opening is blocked while another transient UI has focus.
- Static validation: `.\bin\test_glua_syntax.ps1` passed (145/145); editor diagnostics report no errors; `git diff --check` passed. Live `zn_test_trading`: 14 passed, 0 failed; `zn_test_professions`: 12 passed, 0 failed, on `zz_preview_den` without a map reload.
- The tap/hold input uses `PlayerBindPress` with alias translation, aimed targeting uses `Player:GetEyeTrace`, and the running client/server have not been map-reloaded. References: [GM:PlayerBindPress](https://wiki.facepunch.com/gmod/GM:PlayerBindPress), [input.TranslateAlias](https://wiki.facepunch.com/gmod/input.TranslateAlias), and [Player:GetEyeTrace](https://wiki.facepunch.com/gmod/Player:GetEyeTrace).
- Live acceptance (2026-10-04): the user tested single-service and multi-service/trader NPCs and confirmed tap E, hold-E radial actions, cancellation, target context, and restored cursor/camera behavior work as intended.

## Phase C — Economy, Trading, And Editor Preview

Status: **ACCEPTED by user (2026-10-04; process-restart crate restoration explicitly deferred by user)**.

1. Add an inventory action to drop an item into the world. Spawn a dedicated crate-like entity that represents the selected item and amount, with a readable label above it. Validate item identity and quantity on the server, and make the inventory removal and world drop atomic so a failed spawn cannot destroy the item or a retry duplicate it.
2. Redesign the bank terminal as a clear deposit/withdraw interface with current balance, sensible bundle amounts, validation, and recent transactions. Keep balance changes atomic and server-authoritative.
3. Redesign NPC trading as an item grid:
   - Show item icon and a gold border for mastercraft items.
   - Hover shows relevant stats; selecting an item opens a purchase detail panel.
   - Provide single, 5x, and 10x purchases only when meaningful and affordable.
   - For ammunition, present full-round quantities and valid multiples.
   - Provide bounded quantity entry with plus/minus controls and an explicit purchase confirmation.
   - Recalculate cost and affordability on the server at purchase time; the client display is not authoritative.
4. Update the FGD preview so placed banks, stashes, and NPCs use their configured world models. Add NPC model, animation, and default-animation properties to the editor only where they can be represented accurately in-game.

**Dropped-item contract (confirmed 2026-10-04):** Crates persist across map changes and server restarts; any player may pick them up; unclaimed crates expire after 24 real-time hours. Each drop creates its own crate containing a chosen quantity from one inventory stack, with no merging. If the requested point is obstructed, reject immediately, retain the inventory item, and explain the failure. Pickup may transfer only the amount that fits, leaving any remainder in the crate.

**Progress (2026-10-04):**

- Backpack right-click now offers a quantity-based **Drop** action. The server places one dedicated, labeled crate on the ground 48 units in front of the player and rejects blocked placement without searching nearby.
- Crate creation, inventory removal, and a 24-hour request-idempotency key commit in one SQLite transaction. Public pickup atomically transfers only available backpack capacity; partial pickups retain their remaining instance in the crate. Rows are keyed by profile and logical city cell or safe-zone ID, so reusable BSP filenames and multiple dens do not alias.
- Crates reload when their location loads, survive map changes, and expire using real time. The user explicitly deferred verification across a full GMod process restart at Phase C closure.
- Static validation: GLua syntax passed (149/149), editor diagnostics and `git diff --check` passed. After a same-map reload, live `zn_test_inventory` passed (45/45), including a model-bound ground-contact assertion.
- The user reported that the crate appeared partly underground. Entity placement now offsets the model origin using its actual model bounds, uses those bounds for its collision hull, and anchors the label above the crate. After the reload, the user visually confirmed the crate rests on the floor, its item/count label is readable, and pressing E picks it up into inventory. The user also confirmed a blocked drop rejects without consuming the item, and confirmed the crate restores correctly after gate travel. Server-restart restoration remains to be checked.
- Banking now uses an explicit den-terminal UI instead of automatic cash-bundle deposits on den entry. Deposits/withdrawals update bundles, the profile-scoped account balance, and a persistent character ledger in one transaction; the UI shows the latest 10 records. Live `zn_test_bank` passed 2/2 on `zz_preview_den`.
- NPC trading now presents clickable item tiles with mastercraft highlighting, item/quality tooltips, a selected-offer detail panel, bounded quantity entry, affordable 1x/5x/10x shortcuts, and purchase confirmation. Ammunition displays total rounds. Live `zn_test_trading` passed 15/15, including multi-unit ammo quantities, on `zz_preview_den`.
- `zn_bank` and `zn_den_stash` honor their configured Hammer model keyvalues; `zn_den_npc` honors its configured model and can select an animation sequence with default and idle fallbacks. Invalid models/sequences are logged. These entity/editor changes have static diagnostics but still need visual inspection in the running client and Hammer.
- After a same-map reload, live `zn_test_bank` passed 2/2, `zn_test_trading` 15/15, `zn_test_inventory` 45/45, and `zn_test_characters` 10/10 on `zz_preview_den` (`preview` profile).
- The user caught a runtime trading-panel error: the selected-offer heading and total label passed color/font arguments to the shared label helper in reverse order. After that correction, the user image revealed that the detail panel width was calculated from a docked parent before layout, collapsing the panel to a scrollbar-width strip. The width now derives from the already-sized frame.
- The trading UI now gives the selected-offer sidebar a distinct background and reduces offer tiles to 68x86. Sellable inventory rows also show each item's authored icon or model icon, with the text shifted to preserve space. GLua syntax passed (152/152), editor diagnostics report no errors, and `git diff --check` passed; the preview den was reloaded, and the user confirmed the sell-row icons look good. Three-column offer-grid fit, sidebar appearance, bank and NPC model/animation previews, and Hammer presentation still need visual inspection.
- Removed the weapon-by-weapon magazine-equivalent breakdown from ammunition purchase details; the quantity display now shows only the number of rounds. The server no longer sends unused magazine-capacity metadata.
- Trader offer names now have a black outline and model icons are confined to the upper tile area so captions do not overlap them. Cash and credits balances use white labels with yellow currency amounts across the trader, inventory, bank, mastercraft, and services windows; bank history and other cash totals use the same yellow amount treatment. After a same-map preview reload, the user confirmed the item captions and currency display look good. GLua syntax passed (152/152), diagnostics found no errors, and `git diff --check` passed.
- Added `persisted_dropped_crates_restore_when_the_location_loads` to verify that saved crate rows recreate their world entities after active cell state is discarded. GLua syntax passed (152/152), editor diagnostics report no errors, and `git diff --check` passed. Live `zn_test_inventory` now passes 46/46, including the reload-path regression. This exercises the restoration path against durable SQL rows but is not an actual Garry's Mod process restart; that specific persistence check remains pending.
- After the user reported missing bank and stash previews in Hammer, added their default `studio("...")` models to the FGD class declarations while retaining editable `model(studio)` keyvalues; documented the editor defaults. The user confirmed both previews display correctly in Hammer.
- Bank and stash VPhysics are now motion-disabled and sleeping on spawn. Their crosshair hover prompt identifies **BANK** or **DEN STASH** and says **Press E to interact**. After a same-map preview reload, the live `zn_test_bank` suite passed 3/3, including checks that both entity physics objects have motion disabled; `zn_test_inventory` passed 46/46, and the NPC report contains no rejected configurations. The user visually confirmed the bank window, configured bank/stash/NPC models and animations, Hammer previews, and both hover prompts. The user accepted Phase C and explicitly deferred only the full-process-restart crate restoration check.

**Checks:** Exercise drops across disconnects and map changes, including server-restart restoration and expiry behavior agreed in Phase 0. The focused bank/trading suites cover insufficient funds, full-backpack refusal, multi-unit ammo round counts, stale client prices, and failed/duplicate purchase requests. Live-check bank balances and transaction history, mastercraft presentation, NPC model/animation previews, and the editor-to-world result. Add narrowly scoped admin/development diagnostics for drop ownership/expiry or bank/trade state only if the existing test reports cannot establish the live outcome.

**Exit:** Dropped items and displayed offers match server-accepted state, balances/items cannot be duplicated or lost, and FGD previews match the configured world entities.

## Phase D — 3D Skybox Feasibility Prototype

Status: **ACCEPTED by user (2026-10-04)**. The user approved the runtime skybox across every cell, including the horizon wall, clouds, coast, snow overlay, matched seam lighting, set dressing, fires, and the measured cost, and moved work on to Phase E. The full preview restage noted in the history below remains to be repeated with Phase E's world-generation changes.

**Research (2026-10-04):**

- Garry's Mod's installed `bin/base.fgd` documents `sky_camera` scale `16`, and says the camera origin in the 3D skybox corresponds to the map origin. Its entity definition exposes fog enable/blend, color, start/end, and max-density keyvalues.
- Valve's public Source SDK 2013 `src/game/server/SkyCamera.cpp` at commit [`b8cfb12`](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/game/server/SkyCamera.cpp) maps the scale and skybox-fog keyvalues onto the server entity; its spawn stores the entity origin, and its server defaults/official-map behavior include fog density and radial fog handling. This is HL2 game code, not the Source renderer or the exact Garry's Mod branch, so it does not verify the client transform or visual fog behavior.
- The Garry's Mod Wiki's [`GM:PreDrawSkyBox`](https://wiki.facepunch.com/gmod/GM:PreDrawSkyBox) documents that hook as occurring before 3D skybox drawing and only when a map has a 3D skybox and `r_3dsky` has not disabled it. This does not by itself establish dynamic skybox-fog behavior. The live Valve Developer Community page was blocked by its anti-bot check; an archive was attempted, but the usable engine-side facts above are recorded from the local Garry's Mod FGD and public SDK code instead.
- ZombieSim already owns dynamic skybox fog: `gamemode/cl_atmosphere.lua` handles `SetupSkyboxFog(scale)` and scales the active profile's fog start/end by the engine-supplied scale. The Garry's Mod Wiki's [`GM:SetupSkyboxFog`](https://wiki.facepunch.com/gmod/GM:SetupSkyboxFog) page confirms the hook uses `render.Fog*` and is gated by the presence/enabled state of a 3D skybox. The prototype should test this existing path rather than add a competing fog implementation.
- The first prototype will therefore validate alignment, lighting, fog, and render cost in the actual preview client before any runtime fog integration or per-cell rollout. Propper remains optional: no Propper executable was found beside the installed Hammer binary, and the earlier user deferral did not require that workflow. Do not introduce it unless the prototype demonstrates a need and it is separately approved.
- The current seed-1337 preview plan identifies `zz_preview_efa60f5bcc99.vmf` at logical cell `(6, -9)` as a unique one-cell motorway-straight recipe with an ordinary road on-ramp; its immediate east/west neighbors are road junctions and its north/south neighbors continue the motorway. This is the candidate for the isolated preview build; do not infer more distant scenery from the local tile recipe alone.

**Prototype update (2026-10-04):**

- The first prototype (PHX road props and brush boxes in a room far below the map) was rejected. The magenta surfaces and wireframe lines were caused by replacing a loaded map's BSP and then reloading that same map: the client kept the stale pak directory. The skybox design was not the cause. When staging, always change to another map, confirm that change through the bridge, copy the BSP, then load the target map.
- The on-ramp orientation is fixed by `rotations.transport.onrampRoadByDirection`, and the user accepted it.

**Tile-model prototype (2026-10-04):**

- `bin/build_skybox_cell.ps1 -WorldProfile preview -CellFilename <recipe>.vmf` converts each neighbouring recipe within `vmfBuild.skybox3d.neighbourRadius` into reusable cell models:
  - It converts the brush and displacement geometry of all 49 tile instances (`bin/skybox_models.psm1`).
  - It resolves materials in place from the mounted VPKs (`bin/vpk_reader.psm1`) and writes VertexLitGeneric wrapper VMTs.
  - It compiles the models with studiomdl.
  - It writes a sealed TOOLSSKYBOX room above the map, containing a `sky_camera` at scale 16 and the props.
  - `build_cell_vmfs.ps1 -SkyboxPrototypeCellFilename/-SkyboxPrototypeTemplate` injects that room into one recipe.
- `compile_cell_vmfs.ps1` now compiles against an overlay game directory (`generated/build_<profile>/_compile_game`). Its `cfg/mount.cfg` mounts `garrysmod`, the user's own mount.cfg entries and the gamemode `content` folder. Before this change, VBSP dropped every `models/zombiesim/...` static prop: the Garry's Mod compilers ignore gameinfo SearchPaths and only mount the `-game` folder plus its mount.cfg.
- Result for `zz_preview_efa60f5bcc99`:
  - 32 skybox props across 24 neighbour cells, built from 13 unique recipes (17 model parts).
  - 375 clusters and 1,091 portals, under the 1,350 cap.
  - 96 static props in total. VVIS and VRAD are clean.
- Static checks pass. Live: the user confirmed the skybox looks good with lighting after a clean map load.
- Limitations:
  - prop_static models inside tiles are not represented.
  - Recipe sharing means a skybox is only unique when its target recipe is used by one cell.
  - Remaining checks: frame-time and memory measurement, fog across atmosphere settings, and a decision on per-cell rollout.

**Runtime rollout (2026-10-04):** The user accepted the prototype and asked for every cell to get a skybox, for fog or a dome that hides the void, and for clouds. They chose a runtime design because 576 cells share 167 recipes, so a per-recipe baked skybox would show the wrong neighbours.

- `build_cell_vmfs.ps1` instances one shared skybox room (`zm_skybox_room`) into every city recipe when `vmfBuild.skybox3d.enabled` is set. The prototype parameters and `bin/build_skybox_cell.ps1` were removed.
- `bin/build_skybox_models.ps1` builds models for all 167 preview recipes (188 parts, about 0.96M triangles, 2m20s cold; later runs are incremental). It also writes `content/data_static/zombiesim_skybox_preview.json`.
- `gamemode/cl_skybox.lua` (`ZM_Skybox`) draws the current cell's neighbours in the 3D sky pass, plus the following:
  - A fog-coloured horizon wall.
  - 56 drifting cloud clusters whose cover follows the weather.
  - A client-drawn coastline wherever the ring runs past the world grid: sea, concrete sea wall, and foam. The user chose this over authored coast tiles.
  - Graded skybox fog through `cl_atmosphere`'s `SetupSkyboxFog`.
  - Quality convars `zombiesim_sky_detail` (0–2) and `zombiesim_sky_clouds` are part of the presets.
  - Diagnostics: `zombiesim_skybox_status`, and the `skybox` field of `zombiesim_dev_atmosphere_status`.
- Portal budget:
  - Moving the room's vertical planes onto VBSP's 1024-unit block grid reduced the room's cost on `594c1fb8277a` from +36 to +32 portals.
  - 43 recipes were over the old 1,350 cap. The cause was border tiles that lacked `func_detail`, and the user corrected them. As tile detail grows, the user doubled the diagnostic budgets to 1,500 clusters and 2,700 portals (2026-10-04).
- Static: GLua syntax and both PowerShell scripts parse. Every recipe contains `zm_skybox_room`.
  - Portal check after the `func_detail` fixes: 170 maps, 0 over budget. Portals max 1,197 (average 594); clusters max 375 (average 201).
  - Full preview compile and restage: 169 maps compiled and 1 current, 0 failed or incomplete.
  - Skybox models rebuilt: 167 recipes, 185 parts, about 0.96M triangles.
- Live: pending a visual check of alignment, lighting, the horizon wall, the clouds, the Storm Drain coast, and frame time.
  - The first live load had no models: `util.IsValidModel` returned false on the client for every cell model (missingModels 28) even though the file exists and `ClientsideModel` loads it. Placement now requires only `file.Exists(path, "GAME")`. After `changelevel`, `zz_preview_efa60f5bcc99` shows 28 placements, 0 missing, and 28 models drawn per frame.
  - The user confirmed the skybox looks right and the Storm Drain coast works. They then found that world-space systems were treating the room as part of the cell:
    - runtime foliage, debris, and fallen bodies spawned on the room floor;
    - puddles and snow cover would sample there;
    - the local map capture camera at z=3600 sat inside the room (z 3248–3840), so the MAP view showed the skybox scene.
  - Fix: `ZM_Skybox:GetPlayableCeiling()` returns the sky camera z minus 128 for maps in the skybox manifest, and nil for dens.
    - `cl_foliage`, puddle and snow bounds in `cl_atmosphere`, and the map capture origin clamp to that ceiling. The capture version is now 8.
    - `sv_foliage` (shared with fallen bodies) clamps to the `sky_camera` entity.
    - Static: GLua syntax passes, and foliage and bodies place without errors after `changelevel`.
    - Live visual check of foliage and the MAP view is pending.
  - Snow overlay (implemented; user confirmed visually):
    - `build_skybox_models.ps1` compiles a per-recipe `<recipe>_s<N>` model containing every up-facing renderable triangle (normal z ≥ `snowMinNormalZ` 0.7), lifted by `snowLift` (2 units) and mapped with planar `nature/snowfloor001a` UVs (`zmsky_snow_v1`). Snow parts have their own stamps (`skybox-snow-v1`), so they never recompile the base models. The manifest gains an optional `snow` table.
    - Static: 167 snow parts, 173,529 triangles (about 1k per recipe); GLua syntax passes (153 files).
    - `cl_skybox.lua` draws the overlay after the base models, fading it with `ZM_Atmosphere.SnowCoverAmount` using the ground-cover easing. It draws with `render.DepthRange(0, 1 - 0.00005)` as a depth bias.
    - Live: with forced snow, 16 base placements and 14 snow placements, 0 missing, all drawn at alpha 1. An 8-unit lift z-fought and a 32-unit lift showed as a raised slab at the cell edge; a 2-unit lift plus the depth bias was confirmed clean.
  - Seam lighting (user confirmed visually, clear and snow): skybox models previously used the sky room's own model lighting and showed noticeably brighter than the lightmapped playable road at the cell edge.
    - `cl_skybox.lua` now traces a ring of ground samples 256 units inside the playable bounds once per map (stepping through the cell's sky lid), averages `render.ComputeLighting` per direction every 2 s into a six-sided cube, and applies it with `render.SuppressEngineLighting` + `render.SetModelLighting` for the base and snow models.
    - Client convars: `zombiesim_sky_matched_lighting` (1; 0 restores sky-room lighting) and `zombiesim_sky_light_scale` (user-tuned to 0.2).
    - Live: 61 of 64 samples kept (3 steep), top ≈ 0.81/0.89/0.99, side ≈ 0.07/0.09/0.11. The user tuned the scale live and confirmed both the clear and snowy seam. Weather restored to `auto`, snow cover 0.
  - Set dressing (user confirmed visually): the skyline was barren and the motorway gave long empty sightlines.
    - `build_skybox_models.ps1` adds an optional manifest `detail` table per recipe. It holds the tile's authored props that read at sky scale (trees, hedges, lampposts, containers, dumpsters, billboards, AC units, vehicles; `detailPropPattern`/`detailVehiclePattern`). It adds generated wrecks parked in `CONCRETE/CONCRETEFLOOR037A` road and motorway lanes (`roadCarSpacing` 320, `roadCarChance` 0.35; deterministic per recipe, some skewed across the lane). Fire candidates come from every vehicle plus each tile's highest rooftop (≥ `roofFireMinHeight` 192). Detail needs no model recompile, and every model is checked against the mounted search path.
    - Static: 16,954 props (1,284 generated wrecks) from 43 mounted models, 4,792 fire candidates, 0 unmounted; GLua syntax passes (153 files).
    - `cl_skybox.lua` draws each prop type through one shared, hidden `ClientsideModel` scaled 1/16 with `EnableMatrix("RenderMultiply")` and forced low LOD. Props are re-posed per draw under the matched light cube, in a per-cell priority order (apparent size from the sky camera), with frustum and size culling and a 200-draw budget × `zombiesim_sky_props`.
    - Fires: a stable per-cell hash sets about 6% of wrecks and 8% of rooftops burning (at most 2 per cell, 32 total). Each has additive flickering flames and a glow, plus a 9-puff dark smoke plume that rises, spreads, and drifts with the clouds, sorted back to front and fogged with the sky pass.
    - Quality convars `zombiesim_sky_props` (low 0.4, medium 0.7, high 1) and `zombiesim_sky_fires` (low 0).
    - Live (grid 0,9, 14 neighbours): 805 props, 200 drawn per frame, 22 fires, 187 smoke quads, no material or model errors. Skybox hook cost: 3.4 ms/frame unbudgeted (343–421 draws), 2.1 ms with the budget; p50 frame time 9.3 ms. The user accepted the look.

1. Research and document the applicable Garry's Mod/Source sky-camera scale, fog, lighting, model, and rendering behavior before choosing an implementation.
2. Prototype one preview cell, not a world-wide rollout. Represent nearby cell road layout with reusable road/motorway models and custom skybox buildings; do not place full gameplay tiles or real gameplay buildings into the distant scene.
3. Test skybox alignment at cell edges and across transitions, and verify fog occlusion and lighting consistency at multiple player viewpoints and times/atmosphere settings.
4. Compare model conversion workflows, including a small Propper experiment if appropriate. Do not convert every tile or commit to per-cell skybox generation until the prototype proves visual alignment, acceptable compile/runtime cost, and a maintainable asset workflow.
5. Measure client render cost and memory. Treat moving clouds, dynamic weather, and snow in the skybox as optional follow-up work, not a prerequisite for the first static prototype.

**Checks:** Inspect the prototype in Hammer and in a running preview client; verify cell-edge continuity, fog, lighting, and frame-time impact.

**Exit:** User accepts the prototype and its cost. If it fails, document the evidence and defer or revise the approach before expanding it.

## Phase E — City Generation, Tiles, And Foliage

Status: **ACCEPTED by user (2026-10-04)**. The user confirmed the harvestable/decorative foliage distinction in game, approved the industrial placement and road connections in the generated cell, and approved the industrial/building and road-variant fixtures in Hammer.

1. Add and verify the new tile decorations and industrial building templates. Confirm industrial templates are selected and placed by the planner under intended conditions.
2. Add the requested road and motorway visual variants from the authored templates. Keep selection deterministic for a given seed and validate all rotations/joins.
3. Reduce uninteresting open terrain-only areas without invalidating paths, building access, map navigation, or required transition space. Establish and measure the desired open-tile target before tuning.
4. Increase and diversify foliage placement across valid grass, dirt, and rocky surfaces. Use available mounted tree/bush models and improve composition without placing foliage in roads, buildings, doorways, or inaccessible borders.
5. Confirm ragdolls, trash, and loot remain accessible near the map boundary (Phase A behavior) after density changes.
6. Review the user's edited templates as source. Reconcile removed templates and stale `.vmx` files by checking planner/instance references; do not recreate a deleted template solely because a `.vmx` remains.
7. Rebuild only artifacts affected by current inputs in preview. Run relevant template/planner regressions, required-cell checks, VBSP and visibility budgets when geometry/portals change, then inspect affected layouts in Hammer. Do not assume that all templates require a full world recompile.

**Checks:** Add or extend deterministic stable-seed regressions for road-variant selection, industrial template selection, open-terrain targets, foliage exclusions, and border placement before broad preview regeneration. Compare plans before/after; verify road connectivity, accessible loot, and open-area metrics. Follow the focused preview-generation and compile workflow in [AGENTS.md](AGENTS.md).

**Exit:** The accepted preview has the intended variety and density, all required maps compile, structural/visibility checks pass, and representative generated layouts are visually approved.

**Status (2026-10-04): implementation, full preview rebuild, live service checks, in-game review, and Hammer review complete.**

- Items 1?3 (planner):
  - The `industry` pattern now matches the real `tile_industrial_*` files, which were never placed before. `tile_industrial_1a` gained a south frontage marker.
  - `cellPlanning.openTerrain` turns excess open terrain into decorations. Open terrain went from a mean of 27.3% (max 68%) to 15.1% (max 16%).
  - `cellPlanning.topologyVariants` swaps 317 of 811 eligible straight tiles (39%) to road_a/b or motorway_a/b/c.
  - The preview plan now places 93 industrial tiles.
- Item 4 (foliage): `sv_foliage` places up to 30 nodes from seed-picked pools of 6 tree and 7 bush models, all checked with `vpk.exe`; each full cell now intersperses 10 harvestable resource plants with 20 natural-color, non-harvestable decorative plants. Rock and boulder ground grows bushes only.
- Item 5 (border): the base template wraps the 5x5 grid (?1600) in an inaccessible 640-unit border ring, and the world bounds reach ?2304. The old 256-unit margin therefore let foliage, fallen bodies and client debris spawn up to ?2048, inside the ring. All three now clamp to the playable grid.
- Item 6 (`.vmx` files): removed 18 orphan `.vmx` files that had no `.vmf` and no references, as the user approved. `test_phase_e_layouts.ps1` now fails on any orphan `.vmx`.
- Static checks:
  - `test_phase_e_layouts.ps1 -Replan` passes, and a replan gives an identical plan;
  - the C2, building-frontage and multi-tile tests pass;
  - the `zn_test_foliage` cases cover model pools, rock shrubs, border bounds, and now the 10/20 harvestable/decorative contract;
  - the GLua syntax check passes (153/153 files after the foliage follow-up).
- Item 7 (rebuild):
  - The first VBSP pass showed 19 leaks, all caused by the newly placed `tile_industrial_1a`, which was authored 384 units below the z=0 ground plane. It was shifted up with texture lock, and the user then refined it and fixed non-detail world brushes in `tile_industrial_1a_2x`.
  - `test_phase_e_layouts.ps1` now rejects templates that are not on the ground plane.
  - VBSP: 0 failed. Visibility budgets: 171 maps, 0 over budget, 0 missing `.prt` files, 0 leaks.
  - Skybox models rebuilt: 20,654 detail props, 0 unmounted. Dev zoos refreshed.
  - Full VVIS/VRAD: 168 compiled, 0 failed, 0 incomplete. Staged with the runtime index.
- The user confirmed the plant color/resource distinction, the generated industrial cell's placement and road connections, and the Hammer building/road fixtures.

**Live foliage follow-up (2026-10-04):**

- The user's chosen contract is 30 total foliage nodes per full cell: 10 interspersed harvestable plants and 20 decorative plants. Decorative plants retain natural color, cannot be harvested, and are skipped by nearest-harvest targeting. Harvest-state keys were versioned to avoid applying old harvest records to newly decorative slots.
- Static: `.\bin\test_glua_syntax.ps1` passed (153/153); whitespace and editor diagnostics pass.
- Live after a clean `changelevel` on preview map `zz_preview_c8d614da272e-cp` (logical cell `(12,-7)`, grid `(12,5)`): `zn_test_foliage` 15/15 passed, including deterministic 10/20 allocation and decorative interaction checks; `zn_test_loot_spots` 15/15 passed. `zn_foliage_status` reported 30 nodes (10 harvestable, 20 decorative), 9 trees and 21 berry shrubs; loot diagnostics found 76 matching props and 32 loaded spots.
- The user visually confirmed that the harvestable/decorative color distinction looks right in the live client.
- The user also approved the in-game industrial placement/road connections and the industrial and road-variant layouts in Hammer.
- Carpark follow-up (2026-10-04): paved textures with concrete/road surface properties were already rejected, but a large tree placed on an adjacent eligible patch could overlap the parking surface. Trees now require a four-point suitable-ground footprint; edge candidates become shrubs, and carpark/parking texture names are explicitly excluded. GLua syntax passed (153/153), `zn_test_foliage` passed (16/16), and editor diagnostics found no errors. After reload on preview map `zz_preview_84864e5627e8` (logical cell `(5,3)`), `zn_foliage_rebuild` placed 27 nodes after 360 attempts. The user confirmed the carpark tree/pavement overlap is gone.

## Phase F — Radiation, Damage, And Target Feedback

Status: **ACCEPTED by user (2026-10-04)**. Multiplayer footstep audio and the broader resolution/reduced-effects matrix are explicitly carried into Phase J; exposure sensory controls are implemented in Phase G.

1. Add a cell “DANGER” star rating above the minimap and in the world-map inspector, based on a documented gameplay danger scale separate from radiation.
2. Add a top-right Fallout-style “RADIATION” meter to the live HUD and retain the world-map inspector readout. The HUD uses the Phase 0-approved normalized game intensity mapped linearly to a fictional 0–10 Sv estimate, hides when the displayed value rounds to zero, and does not add an on-panel “GAME ESTIMATE” label; the inspector remains a 0–100% intensity readout. Do not change runtime damage or imply physical calibration.
3. Add directional damage indicators around the screen. Implemented: indicators use actual post-damage events, scale with damage, merge repeated hits, and use a perimeter pulse when no reliable direction exists; client indicators are bounded, avoid reserved HUD panels, and hide for menus/safe zones. The focused server suite passed 3/3; the user visually confirmed multiple-direction and environment feedback on 2026-10-04.
4. Make the crosshair neutral gray without a valid target, then visibly distinguish valid interactables from enemies. Implemented: it is neutral gray with no valid target, gold for a directly aimed searchable loot spot or in-range dropped crate, and red with corner ticks for a live walker/boss. It no longer reflects player health. Static validation is complete; the user visually confirmed the target categories and locked, orbit, and shoulder camera modes.
5. Fix puddle splash rendering artifacts and make player footsteps use the intended puddle-compatible material. **Recovered; singleplayer visuals accepted by the user on 2026-10-04.** The rejected procedural ripple redesign caused an engine index-buffer overflow (`40032>32768`). It has been removed: rain impacts retain the 240-ring/40-crown caps with one quad per ring (maximum 1,440 indices), and the previous footprint/ring appearance and five upward water-splash particles per puddle step are restored. Footprints explicitly rebind their material after rain crowns. The bright streak persisted with the old particle asset; replacing its `SpriteCard` material with mounted `effects/splash2` (`UnlitGeneric`) resolved it, and the user confirmed the footprints and splashes look right. GLua syntax passed 156/156; the atmosphere suite passed 7/7; a fresh rainy preview load recorded 111 weather steps with no new splash/mesh/engine errors. The wet-surface hook profile averaged 1.29 ms/frame before the particle-material correction; it is not a worst-case or final performance acceptance. Puddle-only multiplayer sound replacement and singleplayer layered fallback remain; wet-ground and lying-snow footsteps are preserved. Multiplayer audio remains unverified.
6. Correct map/minimap atmosphere presentation: prevent rain drops, snow drops, and the player from being baked into the map image; refresh captured map imagery when atmosphere changes, but account for the time needed for snow to melt/clear before recapturing. Implemented, live checks pending: capture-scoped player and weather-emitter suppression, including draining particles after a weather change; transient puddle impacts/footprints and target halos are excluded while lying snow remains. Captures restore normal rendering on completion or a reported render error. Minimap captures queue a refresh on weather, snow-amount, and snow-mesh readiness changes, throttled to three seconds; the final melt triggers a clean recapture rather than retaining the earlier snowy image. Open level-view maps retain their existing periodic refresh. User-requested follow-up: minimap loot question marks share the existing nearby loot-marker cache, are gold for available loot and gray for declined loot, and disappear when consumed. Replicated loot-state/removal changes invalidate the captured image so an emptied prop does not retain its old yellow tint. Both level and cell-texture minimap modes use their existing projections. Added capture/loot-revision diagnostics to the client atmosphere status.
7. In shoulder-camera mode only, move overhead looting/progress and other player indicators onto the HUD. Preserve overhead indicators in other camera modes. Implemented, live checks pending: the user chose lower-center HUD rows with search above stamina and player notifications above both. Target search hints also use the HUD anchor; world loot markers stay attached to loot. A shared camera-mode predicate uses the same shoulder threshold as input handling and excludes den first-person mode. Anchors avoid an enlarged minimap; their reserved HUD rectangle covers the notification stack. Locked/orbit overhead anchors remain unchanged.

**Checks:** Test multiple damage directions and environment damage, target categories, camera modes, atmosphere transitions including snow-to-rain, and map reopen/capture timing. Verify danger/radiation stars, damage indicators, crosshair, and prompts at multiple supported resolutions and HUD scales against bright, dark, and snowy scenes; ensure they do not overlap reserved HUD regions. Provide independent options for screen shake and grayscale, and preserve useful information when visual effects are reduced or disabled.

**Exit:** Each readout corresponds to the correct gameplay state, effects remain legible and configurable, and minimap captures represent the current world rather than transient overlays.

**Remaining-item validation (2026-10-04):** GLua syntax passed 156/156, editor diagnostics found no errors, and focused whitespace checks passed. The atmosphere suite passed 7/7 in the deployed preview cell. The user confirmed loot question marks/state refresh, lower-HUD shoulder indicators with unchanged locked/orbit anchors, clean snowy map captures, and recapture after natural snow-to-rain melting. An intermittent black capture patch disappeared after the camera occlusion halo was excluded. A separate rectangular shadow/weapon outline disappeared after capture-scoped player and owned-weapon `NoDraw`/`EF_NOSHADOW` suppression and explicit held-weapon draw exclusion; the user confirmed normal player/weapon rendering afterward. Original flags are restored after capture, including the reported-error path. Final fresh-load diagnostics show capture inactive, matching atmosphere/loot revisions, and no new capture/weapon rendering errors. Phase acceptance remains pending; multiplayer footstep audio, broader resolution/settings checks, and reduced sensory-effect options are not claimed as verified.

## Phase G — Radiation-Responsive Zombies And Gore

Status: **IN PROGRESS**. Phase F was accepted on 2026-10-04. The user chose separate zombie-proximity warnings with unchanged cell-damage behavior, and a mixed radiated walker population whose chance scales from 0% to 50% with cell radiation intensity.

**Initial implementation:** Existing Walker ticket materialization and development enemy spawning now publish `ZM_Radiated` and `ZM_RadiatedIntensity` for ordinary walkers. A separate deterministic ticket-seeded stream selects the variant without changing enemy selection, health, speed, loot, or XP. Nonradiated cells produce no radiated variants; bosses are excluded from this ordinary-walker pass. GLua syntax passed 156/156 and the focused live enemy suite passed 14/14, including two new chance/repeatability/stat-preservation cases. This is spawn-state infrastructure, not completed Phase G presentation: Geiger/proximity feedback, sensory controls, model/gore changes, and zone approach/retreat live checks remain.

1. Spawn radiated zombie variants in designated radiated zones using the existing server-authoritative enemy/population flow.
2. Add proximity-based Geiger-counter audio and visual feedback from cell and nearby radiated-zombie exposure, using the agreed combined-exposure rule. Zero/low exposure must be quiet and visually unobtrusive.
3. Scale grayscale and screen shake to exposure, with clear limits and player options to reduce or disable sensory effects.
4. Use appropriate bloody human model variants for zombies where available and valid.
5. Improve dismemberment blood sprays/decals and evaluate persistent blood pools using the puddle system. Add bloody footprints only if their performance and cleanup cost are acceptable.
6. Treat gore/sensory effects as bounded, quality-configurable effects. Do not let visual blood, audio, or particle work create unbounded entities, traces, or per-frame allocations.

**Checks:** Extend enemy and gore suites for zone selection, exposure state, cleanup, and effect bounds. Live-test radiated and ordinary zones, approach/retreat from a radiated zombie, and inspect visuals/audio with effects enabled and reduced. Provide independently adjustable Geiger audio/visual intensity and gore controls; reduced or disabled effects must not remove gameplay-critical information.

**Exit:** Radiation feedback tracks the agreed exposure model, variants spawn only where intended, and gore/sensory effects remain within measured budgets.

## Phase H — Environment And Safe-Zone Music

1. Add a maintained static music definition registry mapping stable track IDs to safe-zone IDs or environment tags. Keep display names/files separate from gameplay tags so files can be renamed without changing routing.
2. Register the existing music assets and validate files, duration, and mapping. The current audio directory is `content/sounds/music`; inspect its contents and packaging rules before implementing selection.
3. Select a safe-zone-specific or environment-tag track, randomly choosing among lettered variations; fall back to a default when no mapping exists.
4. Schedule playback around a randomized idle interval of roughly ten minutes while respecting track duration. Playback is driven by safe-zone/environment selection, not combat or other moment-to-moment events. Do not cut a track off merely because a timer expires.
5. Fade out before cell/safe-zone transitions and resume the same track at its saved position after arrival, with no overlapping old/new playback or abrupt volume jumps.
6. Add user volume/disable controls and ensure music does not compete unreasonably with gameplay cues such as the Geiger counter.
7. Provide a focused admin/development status report for the resolved environment/safe-zone key, selected track/variation, playback position, and transition-resume state if live tests cannot reliably establish them from normal output.

**Checks:** Validate static definitions (unknown tags/files, missing defaults, duplicate IDs), and live-test default, safe-zone, environment-tag, variation, track timing, transition resume, and disabled/zero-volume cases.

**Exit:** Every supported environment resolves deterministically to a valid track set and transitions preserve the intended playback state.

## Phase I — Movement And Combat Balance

1. Reduce default player walk speed by 10% and sprint speed by 15%; reduce sprint stamina cost by 25% and increase stamina regeneration by 10%.
2. Apply changes through the owning server-authoritative movement/stamina rules, not isolated UI or client-only values.
3. Re-evaluate movement against zombie approach speed, combat, interaction range, and travel duration. Keep final tuning separate from presentation so it can be adjusted without map/content changes.

**Checks:** Add or update focused stamina/movement tests; compare measured walk/sprint duration, drain, and recovery against the old values. Live-test starting, sustained, and interrupted sprint, exhaustion, and representative combat/travel.

**Exit:** The requested percentages are verified against actual runtime values and the user accepts the resulting pace.

## Phase J — Integration And Alpha 3.0 Acceptance

1. Run focused regression suites for every changed subsystem, then the relevant full suite(s); run the GLua syntax check after Lua changes.
2. Complete a preview build only for approved world-generation changes. Review compiler and visibility reports; inspect required maps and the skybox prototype in Hammer. Keep city production assets untouched.
3. Run an in-game matrix covering launcher/deployment, city cell, safe den, NPC/service, full-inventory delivery, bank/trade, drop/loot, atmosphere/radiation, zombie combat, transitions, and movement.
4. Re-profile representative weather/foliage/gore/skybox conditions against Phase 0 baselines. Investigate regressions rather than accepting them as visual-feature overhead.
5. Record known limitations, deferred optional skybox effects, test evidence, and user acceptance for every phase. Only then archive Alpha 3.0 and update [AGENTS.md](AGENTS.md) to name the next active tracker.

## Open Decisions Before The Affected Phase

- Phase B decision (2026-10-04): show provider identity, profession, level, services, and service fee; the first radial includes available services, trade, talk (as an NPC information panel), and a disabled **COMING SOON** placeholder.
- Phase C decisions (2026-10-04): persist bank transactions and show the latest 10; deposit cash bundles explicitly at a den bank terminal rather than on den entry; display ammunition quantities in rounds only.
- Phase F decisions (2026-10-04): danger uses the generated 0–6 tiers directly as 0–6 stars (safe is zero). The inspector radiation readout uses 0–100% normalized game intensity; the user approved a separate top-right HUD meter mapping intensity linearly to a clearly fictional 0–10 Sv estimate. The existing server damage behavior remains unchanged.
- Phase F HUD placement (2026-10-04): show danger stars in a separate panel above the minimap without a numeric star-count label, and radiation in a Fallout-style meter at the top-right; hide the top-right meter when its displayed value rounds to zero, keep both readouts in the world-map cell inspector, and omit the on-panel “GAME ESTIMATE” label.
- Phase G exposure decision (2026-10-04): nearby radiated zombies produce a separate proximity warning channel; existing cell radiation damage intervals and health floors remain unchanged.
- Phase G population decision (2026-10-04): ordinary-walker radiated chance scales linearly from 0% to 50% with cell radiation intensity, retaining existing health, speed, loot, and XP. Boss variant behavior is not changed by this pass.
- Choose the allowed range around the roughly ten-minute randomized music idle interval and what to do if the chosen track file is missing.
- Approve the skybox prototype before expanding it beyond one cell; confirm optional cloud/weather/snow expectations separately.
- Phase E decisions (2026-10-04): open terrain-only tiles must average ≤ 18% across required preview recipes with no recipe above 32% (baseline seed 1337: mean 27.3%, p90 44%, max 68%); harvestable foliage rises from 18 to about 30 nodes per cell with a deterministic per-node pool of mounted tree/bush models; about 35% of eligible plain straight road/motorway tiles become an authored visual variant, chosen deterministically from the cell seed and tile coordinates.
