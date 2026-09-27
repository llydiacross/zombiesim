# Alpha 2.9 (Hud Weapon & Ammo Display Transitions, Fog, Skyboxes, Post Processing Effects, Dismemberment)

- Alpha 2.8 was accepted on 2026-09-27. Its ordinary-zombie corpse search interaction remains an explicitly deferred follow-up.
- Note: Please now keep the current world preview data untouched now for the foreseeable future as all our changes should not required a world re-generation and we will wager when to rebuild vmfs and things like that again due to how long it takes to do it (2 hours)


## HUD Ammo and Ammo Display

- Take a look at https://www.gameuidatabase.com/gameData.php?id=2191&autoload=92004
- Specifically the component which shows the weapon and the ammo
- Please copy exactly that for us for the current weapon and ammo display
- Above that, but in smaller rectangular boxes which display other equipped  and their respective ammo counts.
- when you have that weapon selected, the box is bigger to indicate it is the active weapon, then it shrinks back to the smaller size when it is no longer active.

- Each bullet should be represented visually in the ammo display, allowing players to quickly gauge their remaining ammunition at a glance.
- Only do this for the current clip, as just like the image, the total amount of reserve ammo goes next to the picture of the weapon

## Requirements and small fixes

 - In dens, I was thinking of making it so you are actually first person. So for dens we need to make the player have a first person camera.

 - Transition the camera perspective on transition between first person and top down views, ensuring a more immersive experience.

 - Implement den entrances that allow players to enter and exit dens seamlessly. 

 - Fix border transition gates as they are not working and do nothing

## Add Skyboxes to the cells

 - In the den, there is such a thing as drawing the skybox in a custom fashion in gmod I am sure. I was wondering when you are in a den, we could draw a unique skybox using lua that reflects the environment outside the den, enhancing the immersive experience.

 - Theorise how to take advantage of propper to generate convincing set of skybox models for the different environments to be put in each cell. This will help create a more immersive and visually appealing game world.

## Better Fog

- I want the fog to be really misty like Silent Hill, creating a dense and eerie atmosphere that enhances the sense of immersion and tension in the game world.
- See what source can do for us in terms of fog density, color, and behavior to achieve the desired misty effect.
- Is there anyway to expand further than what source will let us do?
- Experiment with different fog textures and particle effects to enhance the misty atmosphere and create a more immersive environment.
- Note: A fog wall needs to be added around the cell particularly in the transition gates to sort of hide the abrupt changes in the environment and maintain the immersive foggy atmosphere. Kind of like how Civilization games use fog of war to obscure unexplored areas.
- Bug (reported 2026-09-27): after dying and respawning, the view becomes noticeably foggier than it was before death. Check that fog, lighting, and atmosphere profiles actually apply correctly inside Garry's Mod before building any new fog work on top of them. See the Phase E atmosphere audit.

## Cinematic Cell Transitions

- Since we are fixing cell transitions, I would like the transitions to be more cinematic, incorporating smooth camera movements, dynamic lighting changes, and possibly brief cutscenes to enhance the player's sense of immersion and continuity between different cells. 
- The initial idea was for the player to pres e on the transition gate, and then the camere will point to the direction they are about to enter and the player will begin walking forward as the camere stays there but slowly glides upwards, creating a cinematic effect that emphasizes the transition between cells.
- Then, it fades to black, garrysmod loading screen (can we some how figure out how to do the non abrumptive level change and make level changes seamless and smooth for the player) and then seamlessly transition to the new cell without breaking immersion.
- It keeps black, and then when the player spawns, the black then fades out gradually, revealing the new cell and maintaining the cinematic and immersive experience.

## Film Grail Effects and noise

- Implement film grain effects to give the game a more cinematic and atmospheric feel, enhancing the overall visual experience.

## Percicipation

- Implement dynamic weather effects, such as rain, snow, and fog, to create a more immersive and realistic game environment.
- Ensure that precipitation interacts with the environment and player actions, such as leaving wet footprints or causing surfaces to become slippery.
- Experiment with particle systems to achieve visually appealing and believable precipitation effects.

## Ambient Soundscapes

- Implement Source Soundscape system to manage and play ambient sounds, ensuring they are spatially accurate and responsive to the game environment.
- Experiment with layering different ambient sounds to create a rich and evolving soundscape that reflects the changing conditions and events within the game world.

## Dismemberment

- If you are familiar with the dismemberment mod for garrysmod, but it would be very nice to some how integrate dismemberment mechanics into our game, allowing for more realistic and visceral combat experiences. Limbs should be able to be severed and react physically to the environment, adding a layer of depth and intensity to combat scenarios. Blood decals and particle effects should accompany dismemberment events to enhance the visual impact and realism. 

- Increase the variety and realism of dismemberment effects, ensuring that different types of attacks result in appropriate severing and visual feedback. This could include varying blood splatter patterns, limb physics, and environmental interactions to create a more dynamic and immersive combat experience.

- Gore effects should be enhanced to provide a more visceral and impactful experience. This includes realistic blood splatter, body part physics, and environmental interactions that respond dynamically to combat events.

- Note: if a zombie is dismembered their piece is not lootable only the main body it comes from is lootable.

## Blood Decals

- Paired with the dismemberment system, blood decals should be dynamically generated based on the location and severity of injuries. This includes splatters from severed limbs, blood trails from wounded characters, and environmental staining that reacts to player and NPC interactions.
- Consider implementing a system for blood decals to gradually fade over time, reflecting the natural drying and cleaning processes in the game world. This can enhance realism and prevent excessive visual clutter from persistent blood effects. 

## Bullet casings

- Make sure correct bullet casings are used for each firearm, reflecting the caliber and type of ammunition being fired. This adds to the realism and consistency of the game's ballistic system.

## Muzzleflash and tracer effects

- Implement more realistic muzzleflash and tracer effects for firearms. Muzzleflashes should vary based on the type of weapon and ammunition being fired, while tracer effects should accurately represent the trajectory of bullets, enhancing both visual feedback and gameplay immersion.
- Smoke effects should accompany muzzleflashes, with density and duration varying based on the weapon and ammunition type. This adds to the visual realism and helps convey the power and impact of each shot.
- Larger caliber weapons should produce more pronounced muzzleflashes and smoke effects, reflecting the increased power and impact of each shot.

## Other improvements

- Den NPCS added to compass
- Make the waypoint snap to the coordinal directions (N, S, E, W) for easier navigation, if the transition gate is the one for the waypoint it should be yellow instead of the default color.

## World map render-mode layers (implemented 2026-09-27)

- Map layers are now scoped per render mode instead of leaking across every view. `WorldMap.RenderModeLayers` in [gamemode/cl_world_map.lua](gamemode/cl_world_map.lua) declares which layers each mode can draw, and each mode keeps its own toggle state and cookie.
- Atlas keeps the full authored stack and the stacking-order controls. Satellite and Walkers drop terrain, buildings, roads, and motorways because the satellite image already contains them, and default to safe zones, landmarks, and the map key.
- Wireframe draws no map layers, title, boss markers, or map key. It shows only a red cell-boundary grid (1px, semi-transparent, drawn in Lua, culled to the visible canvas and skipped when cells are under 2px), the player, the waypoint and its route, the selected cell, and safe-zone destinations, all drawn directly in Lua.
- Atlas layer preferences keep their existing cookie keys, so saved toggles carry over.
- Static: `./bin/test_glua_syntax.ps1` passes. **Live check remains:** open the map in a client and confirm each mode's layer list, toggle persistence across mode switches, and the wireframe view contents.

## World map zoom resolution (implemented 2026-09-27)

- Deep zoom was blurry because both the satellite and wireframe views magnified a single stitched 4080px atlas, and the per-cell source art was only 240px square. Both bottlenecks are now removed without any world, VMF, or BSP rebuild.
- [bin/build_cell_map_materials.ps1](bin/build_cell_map_materials.ps1) gained `-ResolutionScale` (default 4). It sizes the bitmap up and applies a matching `ScaleTransform`, so every authored 48px-per-tile coordinate stays correct while the output is vector-sharp. Preview recipe maps went from 240px to 960px for 2.93 MB total.
- [bin/build_world_wireframe_material.ps1](bin/build_world_wireframe_material.ps1) gained `-CellImageSize` (default 960) and `-CellDestinationDirectory`, writing one navmesh image per recipe into `content/materials/worlds/<profile>/cells_wireframe` alongside the existing stitched atlas. Identical recipes share a navmesh, so 576 preview cells cost only 163 images (8.26 MB).
- [gamemode/cl_world_map.lua](gamemode/cl_world_map.lua) adds `getCellZoomMaterial` and `drawZoomedCells`. Once the zoomed map exceeds the atlas width, Satellite, Walkers, and Wireframe draw visible cells individually at native resolution instead of stretching the atlas; off-screen cells are culled, so cost scales with the viewport rather than the grid.
- Because the atlas is still stitched from the cell art, the satellite atlas is also sharper now that it downsamples from 960px sources rather than upscaling 240px ones.
- Material memory is bounded by unique recipes, not cells, which matters most for the 64x64 `city` grid.
- Static: `./bin/test_glua_syntax.ps1` and `./bin/test_multi_tile_templates.ps1` pass; only scripts, materials, docs, and client Lua changed. **Live check remains:** zoom each mode to maximum in a client and confirm sharpness, the absence of seams between cells, and frame rate while panning.
- Not done: launcher thumbnails are still built from the previous cell art. Re-run `./bin/build_launcher_thumbnails.ps1` to pick up the sharper sources.
- `zombiesim_map_debug 1` draws a corner readout with the render mode, zoom, current map size, atlas width, and whether the view is drawing the stitched atlas or per-cell images (including how many cells drew and how many were missing). Use it to confirm the per-cell path is actually active before judging sharpness.
- Live: confirmed sharp in a client after a full Garry's Mod restart. Material textures are cached per session, so regenerated PNGs are not visible until the game restarts.

## Level map view capture fix (implemented 2026-09-27)

- The `map` (level view) render mode and the HUD minimap stitch a 2x2 grid of render-target tiles. Each tile was captured by its own perspective camera 3600 units above its tile centre, so all four seams met in the middle of the map. Tall geometry leaned in opposite directions on either side of a seam, which contorted the centre, and only flat ground at z=0 lined up.
- Road markings dropped out because they are overlays coplanar with the road, and perspective depth precision at ~3600 units with a 4-unit near plane was too coarse to separate them.
- `WorldMap:CaptureCurrentMap` in [gamemode/cl_world_map.lua](gamemode/cl_world_map.lua) now captures each tile orthographically with `ortho = { left, right, top, bottom }` sized to the tile span. Tiles stitch exactly at any height and depth is linear. Player, boss, and waypoint projections already used a linear `localMapSpan` mapping, which is now exact instead of approximate.
- `localMapCaptureVersion` moved to 3 so fresh render targets are created instead of reusing the perspective captures.
- First live check failed: the view still tilted (stair and railing sides visible, tall structures leaning) because this Garry's Mod build ignored the `ortho = { ... }` table form, and dropping `fov` let the capture fall back to the wider player FOV. The capture now uses the flat `ortho = true` with `ortholeft`/`orthoright`/`orthotop`/`orthobottom` keys, restores `fov = localMapTileFieldOfView` as the perspective fallback, and moves `localMapCaptureVersion` to 4.
- Second live check: the view was correctly top-down, but tile seams tore through entities and shadows crossing tile edges, a faint line showed along each seam, and the local player was missing. Each tile is now captured with a 128-unit overlap (`localMapTileMargin`) and only its inner region is sampled when stitching, so edge-crossing entities render whole in both neighbours and seam pixels are never sampled. `drawviewer = true` draws the local player, the cull `fov` is widened to 100 (ortho ignores it for projection), and `localMapCaptureVersion` is 5. The margin costs roughly 14% of per-tile texel density.
- Third live check: the player rendered, but the centre tear remained. The 2x2 tiles were replaced by one orthographic 2048x2048 capture created with `GetRenderTargetEx(..., RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, clamp S|T, 0, format)`, so there are no seams to tear. Resolution is unchanged (2048 across the same span). `getLocalMapTiles` is now `getLocalMapCapture` and returns `{ material = ... }`. One confirmed contributor to the tear: the world-map canvas drew tiles through `drawCellCapture`, which never applied the overlap inset, so the margin change misaligned its seam.
- `TEXTUREFLAGS_*` are reference-only on the wiki and never exist as globals, so the first single-capture run errored in `bit.bor`. Clamp S and T are the literal flags 4 and 8, and `RT_SIZE_LITERAL`, `MATERIAL_RT_DEPTH_SEPARATE`, and `IMAGE_FORMAT_*` fall back to their documented values.
- The next run drew a black Map view. A temporary in-engine probe rendered the view into six render-target variants (cleared to magenta first) and read the pixels back at a 1366x749 window. Findings: the default `GetRenderTarget` 1024 target rendered correctly past the window height, so the earlier theory that shared depth tore the 2x2 tiles was wrong; `GetRenderTargetEx` with `MATERIAL_RT_DEPTH_SEPARATE` rendered correctly at 2048 in both RGB888 and RGBA8888, so alpha was not the cause either; an `RT_SIZE_LITERAL` 2048 target with *shared* depth went black below about row 768, which is why the separate depth buffer is required. The capture uses `IMAGE_FORMAT_RGB888` without `$vertexalpha` at `localMapCaptureVersion` 7, and the probe was removed once the map was confirmed. The exact cause of the black run was not isolated: the capture itself was proven correct, and the view rendered correctly after the map reload that preceded the probe.
- Static: `./bin/test_glua_syntax.ps1` passes. **Live: confirmed** - the level view is continuous with no centre tear, road markings render, and the player is drawn.

## Dynamic tree and foliage placement

- Implement a system for dynamically placing trees and foliage throughout the game world, ensuring that vegetation appears natural and varied. Use the texture to determine suitable locations for different types of vegetation, taking into account factors such as terrain type, slope, and lighting conditions. Do this in gmod using Lua script and not as apart of the static map compilation.

- Sometimes, a tree is highlighted yellow meaning you can harvest it with an axe or other appropriate tool to collect wood or other resources.

- Trees might also be harvest for fruits, nuts, or other natural resources depending on the tree type and season. Same as bushes. Bushes might be highlighted yellow when they can be harvested, and they may provide berries, nuts, or other resources depending on the season and bush type.

## Trash Placement

- Implement a system for dynamically placing trash and debris throughout the game world, ensuring that it appears naturally scattered. Bits of paper, broken bottles, and other small debris should be placed in a way that feels organic and responsive to the environment. They should be non collidable to the player but react physically to environmental forces, such as wind or player interactions.

## Looting from shelves

When in the shoulder mode, the players crosshair should be the indicator for what loot spot to search. The loot spot should be highlighted or outlined when the crosshair is over it, providing clear visual feedback to the player. 

## When the player goes under a block or prop

- Currently the camera snaps below the block or prop which can be disorienting for the player. Consider implementing a smoother transition or alternative camera behavior to maintain player orientation and visibility when moving under objects. 
- In top down mode, force the camera to always remain above the player, preventing it from colliding with with world geometry, except in the case where it is in orbial mode, else implement a smoother transition for the camera when moving under objects.
- Consider adding a visual indicator or outline for objects that the player is moving under to help maintain spatial awareness and prevent disorientation.
- Garrysmod has halos built in which can be used to highlight objects that the player is moving under, providing a clear visual cue and helping to maintain spatial awareness.

## More entity loot

- scrape half life 2 vpk models for additional lootable entities and props to expand the variety of items players can find throughout the game world.

- make prop_ragdoll lootable as well, allowing players to search through fallen characters. look at the ragdoll model and determine appropriate loot spots based on the ragdoll type. If its a human ragdoll, maybe there is higher chance to find weapons, ammunition, or personal items like wallets and keys. For other types of ragdolls, adjust the loot accordingly to match the context of the entity. 

## AFK Mode

- It should take a 3 second countdown to open inventory or scoreboard or options menu (cheats menu opens instantly and afks you). AFK Mode means zombies won't attack you. So you are safe to go through your inventory in peace. When you leave the AFK state, you get a couple of seconds of invulnerability to prevent immediate attacks from zombies.

# Hud Notifications

- Display notifications for important events such as leveling up, play a sound to go with it and show a visual cue on the HUD in the center of the screen below the compass and below the xp bar.
- Consider adding different types of notifications for various events, such as quest updates, achievements, or important game alerts, to keep the player informed and engaged.

## Enemy hit markers

- Add call of duty style enemy hit markers that appear on the HUD when the player successfully hits an enemy, providing immediate visual feedback. 
- Add a noise effect or sound cue to accompany the enemy hit markers, providing additional feedback to the player when they successfully hit an enemy.
- Ensure that enemy hit markers are displayed consistently across different screen resolutions and HUD layouts, maintaining clarity and visibility for all players.
- Consider adding different hit marker styles or colors based on the type of damage dealt (e.g., headshots, critical hits) to provide more detailed feedback to the player.

## XP Bar

- Add the experience bar to the hud just below the compass, it should be a solid bar that fills up as the player gains experience points, providing a clear visual representation of the player's progress towards the next level.
- Consider adding different colors or effects to the experience bar to indicate milestones or bonuses, such as a glowing effect when the player is close to leveling up.
- Optionally, display the numerical experience points and the required points for the next level alongside the bar for more precise feedback.

## Implementation Plan

### Source of Truth / Working Rules

- This file is the authoritative tracker for Alpha 2.9 scope, decisions, phase status, and remaining verification.
- Implement phases in dependency order unless a phase explicitly identifies independent work. Record decisions and results here; do not infer completion from code alone.
- **Do not regenerate or rebuild the current preview world or refresh its plans/VMFs as part of Alpha 2.9.** Keep the current preview data and generated maps untouched. Implement against existing runtime data and loaded maps. If a future requirement appears to need a world rebuild, stop and agree on that separately before doing it.
- Preserve the Lua realm boundary: server owns gameplay outcomes, persistence, loot, harvesting, and AFK protection; client owns presentation, camera easing, HUD, and cosmetic effects. Audit and validate every network request and register network strings server-side.
- Reuse existing systems and contracts for `ZM_World`, `ZM_SafeZones`, player progression, inventory, weapons/ammo, loot spots, den interactions, and map transitions. Audit actual APIs before extending them; avoid parallel state or duplicated coordinate/profile resolution.
- All dynamic environmental placement in this milestone is runtime Lua, not static map generation. Derive placement from available loaded-map/world data and traces, with deterministic per-cell selection, explicit entity/particle budgets, and cleanup on cell changes.
- Verify Source/GMod and mounted-game capabilities in a small, reversible prototype before treating them as supported. Do not extract or copy Valve-owned assets into addon content. Propper skybox-model work is a feasibility investigation, not approval to change or recompile map assets.
- Use the linked weapon/ammo image as a functional and layout reference, but create an original ZombieSim presentation rather than a pixel-for-pixel reproduction.
- Keep visual quality settings and effect budgets in mind for multiplayer and lower-end clients. Cosmetic effects must not determine damage, loot, or other authoritative outcomes.
- For each phase, record automated/static results separately from in-client results. GLua syntax validation is required after Lua changes; camera, Derma, HUD, render, sound, and transition behavior also require live-client checks.

### Phase A: Design Contracts, Runtime Audit, and Feasibility Spikes

- Audit the current owners and contracts for the HUD, compass/waypoints, player camera modes, den entry/exit, transition gates, level changes, XP/progression events, weapons/ammo, damage/hit events, lootable entities, player menus, and cell lifecycle.
- Record concrete interfaces/events that later phases can use. Identify client/server boundaries, existing map-transition persistence behavior, and any changes that require a new network message or persistence field.
- Resolve the following before dependent implementation:
  - Define camera mode transitions, den entry/exit triggers, gate activation conditions, and failure/cancel behavior. Preserve logical cell coordinates, safe-zone resolution, and profile/map selection across transitions.
  - Define the cinematic transition fallback: verify whether a truly seamless level change is possible. If not, retain a black fade across the ordinary level load, with reliable pre-load and post-spawn fades; do not promise uninterrupted loading.
  - Verify GMod/Source support and limits for per-cell fog, custom den sky presentation, precipitation, soundscapes, decals, halos, and client rendering hooks. Define a fallback where unsupported behavior cannot be delivered by Lua. The existing atmosphere profiles already show a respawn fog inconsistency; the live audit of that pipeline is the first item of Phase E and gates all Phase E work.
  - Define a bounded visual/weather policy: which precipitation types ship first, whether wet footprints are cosmetic, and whether slippery surfaces are deferred pending movement and gameplay design. Do not introduce movement penalties implicitly.
  - Define how season is represented before seasonal fruit/harvest output is implemented. If the game has no authoritative season/calendar, use a documented fixed/default configuration rather than inventing a clock.
  - Define the player-facing AFK state machine, the exact grace period after leaving AFK, and behavior on death, disconnect, cell transition, or menu cancellation. Protection must be server-authoritative.
  - Define supported dismemberment targets/hit locations, detached-limb lifetime/limits, decal lifetime/limits, and the rule that only the original body remains lootable.
  - Define runtime foliage/trash placement bounds and safe behavior on maps with incomplete terrain/texture data. Confirm that placement can work without world regeneration.
  - Inspect mounted model metadata and existing loot definitions before expanding entity loot. Keep the catalog curated; do not extract/repackage VPK assets or automatically turn every model into loot.
- **Acceptance:** runtime integration points, unresolved policy decisions, feasibility results, and fallback behaviors are recorded here. No dependent work starts on an unverified API or an assumed map rebuild.

### Phase B: Den Camera, Entrances, and Cell Transition Gates

- Implement den first-person camera behavior and explicit, seamless-feeling entry/exit interactions. Keep normal top-down and orbit modes intact outside dens.
- Add eased transitions between first-person and top-down views, including correct camera state restoration after den exit, death/respawn, cancellation, and map load.
- Diagnose and repair the currently nonfunctional border transition gates using the existing world and transition APIs. Validate both activation and destination resolution; do not bypass profile-aware map lookup.
- Add the planned cinematic gate sequence: orient the camera toward the destination, move the player forward only if the server-approved transition flow permits it, raise/glide the camera, fade to black, perform the supported map load, then fade in after the destination spawn is ready.
- Keep the screen black if destination loading/spawn is delayed or fails; prevent duplicate gate activation and ensure transition state is cleaned up on disconnect or failure.
- Snap waypoint direction to N/S/E/W and highlight the waypoint's corresponding transition gate yellow. Preserve other gate styling and compass behavior.
- **Acceptance:** enter/exit dens repeatedly without camera lock or mode drift; exercise all four gate directions and confirm logical destination coordinates, safe-zone id, and map path; verify black/fade recovery and waypoint-to-gate highlighting in a live client. The preview world remains unchanged.

### Phase C: HUD, Weapon/Ammo Readout, and Player Feedback

- Build the weapon/ammo HUD from the existing equipped-weapon and ammo contracts. Show the active weapon prominently, other equipped weapons in smaller boxes, and clearly distinguish the selected weapon.
- Represent each round in the **current clip** visually; show reserve ammo numerically beside the weapon image. Cover empty clips, unsupported/unlimited ammo, reloads, weapon swaps, no active weapon, and screen-size scaling without inventing ammo state.
- Add the XP bar directly below the compass, driven by authoritative progression values. Show progress toward the next level and optionally numeric current/required XP where the layout remains legible.
- Add a small, queued HUD notification system below the compass and XP bar for level-ups and other currently supported important events. Include a matching sound cue, duration/priority rules, and duplicate/rate limiting; leave quest/achievement types as extension points until those systems exist.
- Add enemy hit markers from confirmed damage/hit events, with distinct and tested feedback for supported headshot/critical cases. Avoid a hit marker for a client-only prediction that the server rejects.
- Add den NPC compass markers using existing NPC identity/location data, and integrate the cardinal waypoint/gate state from Phase B without overlapping or obscuring existing markers.
- **Acceptance:** test ammo UI against clip/reserve changes, reload, weapon switching, and empty states; test XP progress and level-up notification; test hit/no-hit and supported damage categories; verify NPC/waypoint markers and all elements at multiple screen resolutions in a live client.

### Phase D: Weapon Firing Presentation

- Audit the existing weapon firing hooks and mounted effect/model assets. Create a weapon/ammo presentation mapping for casing model/effect, muzzleflash, tracer, and smoke, including sensible defaults for existing weapons.
- Select casing appearance by weapon/ammo definition where available, and ensure casings spawn only for weapons that eject them. Avoid attaching real-world caliber behavior to an item unless the game's ammo definition supports it.
- Vary muzzleflash and smoke size, density, and duration by weapon/ammo class; larger-caliber behavior is a data-driven tuning choice, not a duplicated per-SWEP implementation.
- Tracer visuals must follow the actual shot direction and remain visual-only. Respect server-confirmed firing where feasible, avoid false tracers for rejected shots, and prevent effects from revealing hidden information beyond normal projectile visibility.
- Add cleanup, distance/visibility culling, and per-player effect limits so repeated fire cannot create unbounded entities or particles.
- **Acceptance:** live-fire representative pistol, automatic, shotgun, and larger-caliber weapons; confirm casing selection, muzzleflash/smoke variation, tracer direction, top-down aiming consistency, cleanup, and no gameplay/damage changes.

### Phase E: Fog, Weather, Soundscapes, and Sky Presentation

- **First: audit the existing atmosphere pipeline in a live client.** This must pass before any fog, weather, or sky work below; otherwise new effects are tuned against an unknown baseline.
  - Current owners: [gamemode/cl_atmosphere.lua](gamemode/cl_atmosphere.lua) handles `SetupWorldFog`, `SetupSkyboxFog`, and `RenderScreenspaceEffects` colour correction. `GM:SendPlayerAtmosphereProfile` in [gamemode/init.lua](gamemode/init.lua) sends the profile id on spawn, status reconcile, and from [gamemode/sv_player.lua](gamemode/sv_player.lua) cell moves. The client re-derives the profile from `CellX`/`CellY` NWInts on `ZM.RefreshPlayerData` and `InitPostEntity`. Profiles come from runtime world data via `ZM_World:GetAtmosphereProfileByIndex`.
  - Reported defect: fog is visibly denser after death and respawn than on first spawn. Establish which state is correct before fixing anything.
  - Hypotheses to discriminate:
    - (a) **First-spawn race.** `ZM.SetAtmosphereProfile` arrives before client world data loads, so `ApplyProfile` fails silently. The hooks then return false, and the map's own `env_fog_controller` fog shows until the respawn applies the real profile. In that case the post-respawn fog is the correct one.
    - (b) **Stale re-derivation.** `ApplyPlayerProfile` reads NWInts that have not replicated yet after `ZM.RefreshPlayerData`, and picks a different cell's profile.
    - (c) **Engine fog-controller reset.** On spawn, Source reassigns the player's fog controller or tonemap, changing the map baseline that Lua fog competes with.
    - (d) **Non-zero `StormIntensity`** or a second fog/colour hook from another addon.
  - Add an admin/debug diagnostic, for example a `zombiesim_atmosphere_status` console command or a `zombiesim_atmosphere_debug` overlay. It reports the active profile index and id, the expected profile for the persisted cell, whether world data had loaded when the profile arrived, the applied fog start/end/density/colour, the storm intensity, and whether each hook returned true. Log each profile application with its trigger (net message, player-data refresh, `InitPostEntity`).
  - Live matrix: first join, death and respawn, `zn_preview_start` reload, a cell move through a gate, and a safe zone versus an open cell. For each, compare the diagnostic output and a screenshot against the profile in the runtime world data. Also check lighting and tonemap (`env_tonemap_controller`, `light_environment`, map brightness) for the same states, because colour correction stacks on top of map lighting.
  - Fix the confirmed cause so the same cell always renders the same fog, colour correction, and brightness regardless of spawn history. For (a), queue or retry the profile until world data is ready rather than dropping it. The fix must not require regenerating or recompiling maps.
- Prototype Source fog behavior and record effective density, color, distance, and per-cell control limits. Implement the strongest stable mist effect supported by the engine without making navigation or combat unfair.
- Add a runtime fog boundary/wall around cells and transition gates to disguise abrupt environment edges. Use a tested, budgeted presentation technique and provide a fallback that does not require regenerating the preview maps.
- Implement the approved first precipitation slice (rain and/or snow) as a runtime effect with cell/environment configuration, lifecycle cleanup, and particle budgets. Keep precipitation cosmetic until wet-footprint and slippery-surface behavior has an explicit contract and feasible implementation.
- If wet footprints are in scope after the Phase A spike, make them short-lived, cosmetic, and bounded; do not change surface friction or player movement in this phase without a separately approved rule.
- Integrate Source Soundscapes for spatially appropriate ambient layers. Define how a cell/den selects its soundscape, how layers blend/change with weather, and how duplicate loops are stopped at transitions.
- Implement a distinct den sky presentation reflecting the surrounding environment, but first confirm what can be drawn reliably in the current den rendering setup. Prototype Propper-generated skybox models only as a documented feasibility path; no template edits, VMF generation, compilation, or world rebuild are part of this milestone.
- Add film grain/noise as a restrained, configurable client post-process effect with a disable/quality setting and safe handling across camera modes, menus, and transitions.
- **Acceptance:** the atmosphere diagnostic shows identical fog, colour-correction, and lighting values for the same cell across first join, death/respawn, map reload, and gate transition, matching the runtime profile; the respawn fog regression is closed with the confirmed cause recorded. Test fog boundary visibility and gate concealment in representative existing maps; test precipitation/sky/sound transitions and cleanup; confirm rendering fallback, client performance, and post-processing behavior in a live client. Record unsupported Source capabilities and deliberate deferrals.

### Phase F: Runtime Foliage, Harvesting, and Ambient Debris

- Implement server-coordinated, runtime-only foliage placement using existing cell/world metadata, material/texture observations where available, surface traces, slope checks, and exclusion zones. Do not edit or regenerate map assets.
- Make placement deterministic for a profile/cell, bounded by density and entity budgets, and stable for players sharing a cell. Define cleanup and reuse behavior when the cell unloads/reloads.
- Curate tree and bush types with mounted model paths and resource tables. Add harvest eligibility/highlighting (yellow when harvestable), appropriate-tool checks, server-side cooldown/availability, and inventory grants through existing item APIs.
- Add fruit/nut/wood/resource outputs only through validated item definitions. Seasonal variations depend on the Phase A season decision; prevent repeated requests, client-selected rewards, and harvesting through cell changes.
- Add scattered paper, bottles, and other selected debris as low-cost, non-player-colliding entities. Allow only bounded cosmetic response to wind/player interaction; define whether debris is client-only or shared based on tested physics/network cost.
- **Acceptance:** verify placement on varied existing surfaces, deterministic multiplayer agreement, exclusion of unsafe/blocked locations, harvest eligibility/tool checks/reward uniqueness, cell cleanup, and debris collision/performance behavior. Confirm no generated world data changed.

### Phase G: Dismemberment, Blood Decals, and Gore Lifecycle

- Integrate dismemberment with the existing server-confirmed damage/death pipeline. Define eligible enemy/body models and hit regions; choose sever effects from attack/damage context rather than client-provided claims.
- Spawn detached limbs with bounded physics/lifetime and blood effects. Detached pieces are cosmetic/non-lootable; the originating main body remains the sole lootable corpse. Ensure corpse identity and loot availability cannot be duplicated by severing or cleanup.
- Add blood decals/splatters and, if supported by runtime hooks, trails from wounded entities. Tie placement to confirmed impacts/severing and keep effects cosmetic.
- Fade/remove decals and body parts after a configured lifetime; cap per cell/player, clean them up on map transition, and respect engine decal/entity limits.
- Keep gore effects and blood intensity data-driven so the tested implementation can be reduced or disabled without changing damage or loot behavior.
- **Acceptance:** test multiple attack types and body regions, main-body loot before/after dismemberment, limb non-lootability, effect cleanup, repeated combat under caps, and server/client consistency in a live session.

### Phase H: Loot Interaction and Expanded Entity/Ragdoll Loot

- Improve shoulder-mode shelf/container looting by using the crosshair trace as the target indicator. Highlight only a valid, available loot spot while the crosshair is over it, and provide clear feedback for blocked, empty, or out-of-range spots.
- Preserve existing loot roll, inventory, and server authority. The highlight is a client affordance; the server revalidates range, target identity, availability, and resulting loot on interaction.
- Audit mounted Half-Life 2/GMod model metadata and current semantic loot mappings. Add a curated list of suitable lootable entity/model families with stable definitions; do not scrape assets into addon content or blindly register every VPK model.
- Add supported `prop_ragdoll` loot handling through an explicit model/type-to-loot mapping. Human ragdolls may use an approved human loot group; other supported types receive contextual groups, and unknown models safely remain non-lootable.
- Keep loot state attached to the original body/entity identity. Prevent detached limbs, duplicate ragdolls, repeated searches, model changes, or entity recreation from granting duplicate loot.
- **Acceptance:** shoulder-mode target indication is tested for valid/invalid/range/occluded targets; curated entity models resolve to the intended loot group; representative human and non-human ragdolls follow the server-owned loot lifecycle; unknown models fail closed; inventory and persistence regression tests pass.

### Phase I: AFK Mode and Safe Menu Flow

- Implement the three-second countdown when opening inventory, scoreboard, or options. Opening the cheats menu remains immediate and marks the player AFK as specified.
- Model AFK as an explicit server-owned player state, not a client-only menu flag. While AFK, zombies must not select or attack the player; define how active attackers/targets are released and ensure the state cannot be spoofed by arbitrary client messages.
- On leaving AFK, apply the agreed short, bounded invulnerability grace period. Clear protection reliably when it expires and avoid granting repeated or permanent protection by menu toggling, retries, or transitions.
- Handle opening/canceling/closing during the countdown, overlapping menus, death/respawn, disconnect/reconnect, den/cell transitions, and already-AFK players. Keep the countdown and safe-state feedback understandable and accessible.
- **Acceptance:** live-test every named menu, countdown cancellation, cheats-menu immediate AFK, zombie acquisition/attack suppression, exit grace period, repeated toggles, death, and cell transitions. Confirm server-side damage and targeting remain authoritative.

### Phase J: Integration, Regression, and Alpha 2.9 Readiness

- Update directly related HUD, camera/transition, weather/effect, foliage/loot, and gameplay documentation and static data definitions. Keep generated artifacts and runtime exports as pipeline outputs; do not refresh or rebuild the preview world.
- Run the GLua syntax check after Lua changes, then the narrowest affected automated suites for weapons/ammo, inventory/loot, progression, camera/transition, NPC markers, and AFK/combat behavior. Add focused tests for new contracts where existing suites do not cover them.
- Run a live-client matrix covering HUD/camera/Derma/render/sound/transition behavior; server and multiplayer checks for gates, AFK, harvesting, loot authority, and entity cleanup; and representative combat/effect performance.
- Verify that cell transitions preserve profile and logical coordinates, that denied/failed interactions do not mutate persistent state, and that all transient entities/effects/UI state are cleaned up.
- Inspect repository status and generated-artifact timestamps/diffs to confirm preview maps, plans, VMFs, BSPs, and runtime world data were not regenerated or modified.
- Record automated/static results separately from live-client results, document blocked or engine-limited items, and list deferred work before closing the milestone.
- **Acceptance:** focused automated checks pass; each shipped client feature has been exercised in game; multiplayer-sensitive outcomes are server-authoritative; no preview world regeneration occurred; known limitations and follow-ups are explicitly recorded.

## Cross-Phase Rules

- Phase A decisions gate dependent work. If a feasibility spike disproves an approach, record the supported fallback before implementation continues.
- Phase B gates camera/transition-dependent work; Phase A gates all work. HUD work may proceed independently after its runtime audit, while weapon effects require the Phase D weapon/ammo mapping and dismemberment requires the existing damage/death contract.
- Do not replace existing HUD, loot, inventory, map transition, or world-coordinate services when a focused extension will satisfy the feature.
- Avoid persistent data changes unless required and explicitly designed. Any new persistence field needs migration, profile scoping, reconnect behavior, and regression coverage.
- Every dynamic system needs explicit ownership, bounds, cleanup, and failure behavior. Client visuals never grant resources, suppress authoritative damage, or decide a transition destination.
- Mark a phase complete only after its stated acceptance checks pass; clearly label any static-only verification or live blocker.

## Scope Coverage

- HUD weapon/ammo boxes, clip bullets, reserve ammo, XP bar, event notifications, enemy hit markers, and den NPC compass markers: Phases C and J.
- Den first-person view, perspective blending, entrances/exits, transition gates, cinematic transitions, cardinal waypoint snapping, and gate highlight: Phases A, B, and J.
- Cell/den sky presentation, fog, fog boundaries, weather/precipitation, film grain/noise, and Source Soundscapes: Phases A, E, and J.
- Dismemberment, blood decals/trails, gore effects, non-lootable detached pieces, weapon casings, muzzleflash, tracers, and smoke: Phases D, G, and J.
- Runtime tree/foliage placement and harvest, seasonal resources, trash/debris, shoulder-mode loot targeting, curated mounted entity loot, and lootable ragdolls: Phases A, F, H, and J.
- Three-second menu countdowns, immediate cheats-menu AFK, zombie safety, and exit invulnerability: Phases A, I, and J.