# Alpha 2.8.5

Before we move onto Alpha 2.8, we need to work on the launcher rooms and implement a proper menu system.

The idea is that we will load into the loader room and instead of the normal prompt the immediately deploy, that is now replaced with a menu screen. On this menu screen I really want it to base it off of the "Black Ops 2 Zombies" menu, with similar layout, animations, and interactive elements. With the globe on the right side of the screen, rotating and providing a dynamic background element, while the menu options are displayed on the left side, allowing for easy navigation and an immersive experience.

- We will need to create a globe model that can rotate smoothly and provide a dynamic background element for the menu screen.

- Through the menu you can then select which character you would like to play in the world. Or create new one, finally making a way to choose your job profession.

- Also, this will fix the player currently not having a player model as when you make a new character the menu will allow you to select and assign a player model.


## New Character Screen

- When you make a new character, it is broke down into a series of UI flows:

- First, you select which character slot you want to use or create a new character. You get up to three.
- Next, you choose your character's appearance, including gender, facial features, and other customizable options.
- Finally, you select your character's job profession, which will determine their starting abilities, equipment, and role within the game world.
- Once you've picked your profession, now you spend your default starting points to allocate skills, abilities, and other character attributes, allowing you to further customize your character's strengths and playstyle.
- After allocating your starting points, you can review and confirm your character's details before finalizing the creation process.
- Once confirmed, your new character will be saved to the selected character slot, and you will be able to start playing with them in the game world.

## Load Character Screen

- When you want to load an existing character, you will be presented with a screen displaying your available character slots.
- You can select a character from the list to load into the game world.
- If a character slot is empty, you will have the option to create a new character in that slot.
- This screen will also allow you to delete characters if needed, providing a way to manage your character roster efficiently.

## Options

- A mirror of the options menu accessible via the radial menu but accessible here

## Exit to Gmod

- This option will allow the player to exit the game and return to the Garry's Mod main menu. It provides a convenient way to leave the game without having to close the entire application.

## Credits

- This section will display the credits for the game, including the development team, contributors, and any third-party assets or libraries used. It provides recognition and acknowledgment for those who have contributed to the game's creation.

- We should make the credits scroll vertically, similar to traditional game credits and hide the menu and have a nice cut scene or background animation playing while the credits are displayed.
 - Maybe we can build the launcher to be a custom rigged hammer level to achieve this?
- The camera should move around the credits room, zoom in on one dancer, orbit around that ragdoll, then pull back to the room and move on to the next dancer. The dancers' faces should be posed with big smiles.

## Things to consider

- The globe

 The globe is the main visual element of the menu. There is a few ways to achieve this, We could draw a 3D object and give it a material all through code. Or go through the effort of making it a source model and importing it into the game. Each approach has its own trade-offs in terms of performance, flexibility, and visual fidelity.

- Lighting and atmosphere

 The lighting and atmosphere of the menu can greatly impact the player's first impression. Consider using dynamic lighting, shadows, and environmental effects to create a visually appealing and immersive experience. Balancing performance and visual quality is key to ensuring a smooth and enjoyable menu experience.

## Globe Effects

- It would be nice to put a dot on the globe representing the characters current location in the game world on the globe. This is deduced by using the location of the player when they make a new character, so we can save the location they were at when they made this character and present it on the globe. That way, the "city" that character lives in, gets mapped accurately on a real globe. This can enhance the player's sense of immersion and connection to the game world. If you need an example of how I want it to look, I pretty much want it to look exaclty like the planet from citiesxl. can be found here: https://citiesxl.fandom.com/wiki/Planet

## Implementation Plan

### Source of Truth / Working Rules

- This file is the authoritative tracker for Alpha 2.8.5 scope, decisions, phase status, and remaining verification. Alpha 2.8.5 is completed before Alpha 2.9 starts; [todo-alpha-2.9.md](todo-alpha-2.9.md) is queued behind it.
- Implement phases in dependency order. Record decisions and results here; do not infer completion from code alone.
- **No world regeneration.** Nothing in this milestone regenerates or recompiles the preview or city world, plans, VMFs, BSPs, or runtime world JSON. The launcher maps (`celltemplates/launchers/zn_*_start.vmf`) are the only maps in scope. They are small, sealed, and compiled on their own into `generated/launcher_build`, then staged to `content/maps`. They are never part of a world build.
- **Hammer owns placement, Lua owns behaviour.** Camera positions, the globe position, and scene props are authored in the launcher VMFs by `targetname`. Lua looks them up by name and must not hard-code coordinates, so the rooms can be moved in Hammer without code changes. Both launcher VMFs stay identical apart from `zn_world_profile.world_profile`.
- **Server-authoritative characters.** The server owns character slots, creation validation, point allocation, appearance allowlists, deletion, and which character is active. The client only presents choices and sends requests, and each request is validated and rate-limited.
- **Original presentation.** Black Ops 2 Zombies (menu layout and motion) and the Cities XL planet (globe look) are style references only. Do not copy their art, audio, fonts, or UI assets. Every texture that ships needs a recorded licence (for example, public-domain NASA Earth imagery) and a credits entry.
- **Existing players keep their progress.** Current `(steamid, profile)` saves become each player's first character. No progression, inventory, credits, implants, trades, or den stash data is lost or duplicated.
- Preserve the Lua realm boundary and existing style. Register network strings server-side before sending. Reuse `ZM_UI`, `ZM_DermaSkin`, `ZM_Options`, `ZM_Professions`, `ZM_StaticData`, `ZM_World`, and `ZM_TestHarness` instead of building parallel systems.
- For each phase, record automated/static results separately from in-client results. Run `./bin/test_glua_syntax.ps1` after Lua changes. Derma, render, camera, and map-transition behaviour also needs a live-client check.

### Release Slices

The phases ship in three slices so a usable build exists before the presentation work is finished:

1. **Slice 1: characters (Phases A–E).** The launcher menu shell with New Character, Load Character, Options, and Exit to GMod, backed by three persistent character slots. It includes the appearance and player-model fix and profession choice. The globe position shows a static placeholder panel. This slice alone closes the missing-player-model bug and the GDD's three-character requirement.
2. **Slice 2: globe (Phase F).** The rotating globe, lighting, atmosphere glow, and character location dots.
3. **Slice 3: credits and polish (Phases G–H).** Scrolling credits with a background sequence, menu motion and sound polish, and performance tuning.

### Phase A: Design Contracts and Feasibility Spikes

- **Character identity and scope. Decided 2026-09-27: slots are per world profile.** `city` and `preview` each have their own three slots, because every existing table is already profile-scoped and a character's position, inventory, and den stash only mean something inside one world. The stable key is `(steamid, profile, slot)` with slot 1–3, plus an immutable `characterId` for logs and ledgers.
- **Persistence migration strategy.** Every player-owned table is keyed on `(steamid, profile)`: `player_attributes`, `player_data`, `player_items`, `den_stash_items`, `equipped_weapon_slots`, `profession_claims`, `player_implants`, `player_credits`, `credit_ledger`, `mastercraft_attempts`, and `trade_ledger`, plus the per-SteamID bio file. The current code has 53 SteamID-keyed persistence call sites across 9 server files. Choose between:
  - (1) adding a `slot` column and rebuilding each table with the new primary key (SQLite cannot alter a primary key) in one transaction; or
  - (2) keeping the schema and substituting a composite owner string.
  - Recommendation: option 1 with a schema-version table, a pre-migration copy of `sv.db`, and an idempotent migration that assigns existing rows to slot 1. Either way, add one `ply:GetCharacterKey()` accessor and route every persistence call through it, so no call site keeps using `SteamID()` directly.
  - Confirm which systems identify *other* players by SteamID (trading, profession offers, den NPC providers) and switch them to the active character where the record belongs to a character.
  - **Implementation decision (2026-09-27): option 2.** `characters` owns `(steamid, profile, slot)` and an immutable `characterId`; each existing player-owned table retains its `steamid` column/primary key but stores `characterId` there. The one-time transaction rekeys existing rows to migrated slot 1 and records a schema version. This avoids rebuilding eleven SQLite tables and their indexes. The backup and migration must still be verified on a copy of the actual `sv.db` before accepting Phase B.
- **Launcher flow state machine.** The current flow is: spawn → the server loads persistent state → `HoldLauncherTransition` → the client shows the Volt/Walker prompts and then BEGIN → `ZM.DependencyPromptsReady` → `ContinuePlayerSpawnMapTransition`. Define the new states:
  - `no_character`: the player is spawned in the launcher with no gameplay state loaded, and `Save` refuses to write.
  - `dependency_prompts`: the Volt/Walker prompts are kept and shown before the menu.
  - `menu`.
  - `creating`.
  - `character_selected`: the server loads that slot's state.
  - `deploying`: the existing continue transition runs.
  - Define cancel and back behaviour at every step, and what happens on disconnect mid-creation.
- **Active character across level changes.** A level change reloads the player, so the chosen slot must persist server-side (for example, an `active_character (steamid, profile, slot, selectedAt)` row) and be read in `PlayerSpawn` on non-launcher maps. Define the rule for a player who joins a cell map with no active character: send them back to the launcher. Never silently create a character.
- **Existing-player migration UX.** A migrated slot-1 character has progression but no name or appearance. Define it as "named from the Steam nickname, appearance required": on first load, the menu routes it through appearance selection only, then deploys. This is also how existing players get a player model.
- **Appearance feasibility spike.** Confirm what GMod can deliver reliably:
  - selecting a model from an allowlist (the HL2 citizen male/female player models shipped with GMod);
  - skins and bodygroups per model;
  - matching viewmodel hands via `player_manager.TranslatePlayerHands`;
  - player colour.
  - Record whether facial features beyond "choose a face/model" are practical: flex weights are per model, unreliable across models, and not persisted by the engine. Default: gender and face come from the model choice, skin and bodygroups are selectable, and flex sliders are deferred.
  - Define an appearance catalog in `content/data_static` validated by `sv_static_data.lua`, like the other static definitions.
- **Creation rules.** Define name validation (length, character set, trimming, uniqueness per player), the starting point pool (currently `GM:NewPlayer` grants 10 `SkillPoints`), which attributes can receive points, the per-attribute cap at creation, and whether unspent points carry into play. Profession `statBonuses` stay derived at runtime through `ZM_Professions:GetStatBonus` and are shown separately; they are not baked into stored attributes.
- **Deletion rules.** Deletion only happens from the launcher, never for the character that is currently loaded. It needs a confirmation step (type the character's name), one transaction across every character-owned table plus the bio, and a server log line. Decide whether a deleted slot's shared-economy records (`trade_stock` is not player-owned) need any cleanup.
- **Globe technology spike.** The globe is now a 3D object in the menu room, positioned by `menu_globe`, rather than a flat panel. Prototype a textured sphere drawn in the world (a Lua `Mesh` UV sphere in `PostDrawOpaqueRenderables`/`PostDrawTranslucentRenderables`) and compare it with a compiled `.mdl` sphere shown through `ClientsideModel`. Frame it on the right of the `menu_camera` view with the options on the left. Record frame time at 1080p, texture memory, seam and pole artefacts, and whether lighting can be controlled from Lua (`render.SuppressEngineLighting`, `render.SetModelLighting`) independently of the room's baked light and fake-fog walls. Recommendation: the Lua mesh, because it needs no model compile and supports custom shading for the Cities XL night-lights look. Pick a public-domain base texture (for example, NASA Blue Marble / Black Marble) and a texture resolution budget.
- **Geographic model for character dots.** The worlds are procedural and have no real-world coordinates. Define a per-profile geographic anchor (`latitude`, `longitude`, city label, approximate extent in km). Store it in static data, not world generation, so it needs no regeneration. At creation, a character records its profile and starting cell (the origin safe zone, because a new character starts there). Its dot sits at the profile anchor, with the cell mapped to a small offset inside the city extent that only matters when zoomed in. Record whether the dot should follow the character's latest saved cell (recommended as a later option) or stay at the creation location, as requested.
- **Launcher scene contract (authored 2026-09-27).** Both launcher VMFs now contain two areas inside one sealed skybox shell (`tools/toolsskybox`, quick-hidden in Hammer; it spans x -448..448, y -448..1120, z -192..448, with `skyname sky_day01_01`):
  - **Menu room:** x -256..256, y -256..192, z 0..256. It has `effects/fake_fog03` walls, one warm `light` at (0, -32, 224), and `info_player_start` at (0, -192, 33) facing north (yaw 90). The player spawns here. The globe is rendered in this room.
  - **Credits area:** north of the menu room, beyond a building frontage with columns (y 320..392). It is a street with a concrete floor (y 320..1024), a brick wall and awning on the west side with two graffiti `infodecal`s, and three coloured `light_spot`s (magenta, blue, green) around (40..80, 632..696, 160). They light `prop_ragdoll` `dancing_gman` (`models/gman.mdl`) at (-24, 568, 8). A `light_environment` (pitch -85) provides the sun.
  - **`credits_camera`:** a `point_camera` at (128, 832, 120), angles 0 230 0, FOV 90, fog start 2048, end 4096, colour black, maximum density 1. It looks south-west at the G-Man and the spotlights.
  - **Gaps to resolve:**
    - **No menu camera.** The menu room has no camera entity. Recommendation: add a second `point_camera` named `menu_camera` for the menu view, and an `info_target` named `menu_globe` for the globe's centre. Until they exist, Lua falls back to the `info_player_start` eye position facing north, with the globe in front of it.
    - **`credits_camera` starts active.** It has no spawnflags. An active `point_camera` can render the `_rt_Camera` monitor texture, but we only use it as a marker. Set its *Start Off* flag in Hammer (and on `menu_camera`).
    - **Dance floor: resolved with a physics wind rig (entity ids 2001–2320 in both VMFs).** The dancers stay `prop_ragdoll`s and are moved by physics, not animation:
      - **Dancers:** `dancing_gman` (-24, 568; placed in Hammer), `dancing_alyx` (-108, 720), `dancing_barney` (-136, 568), and `dancing_kleiner` (112, 480). They are placed inside the `credits_camera` view: Alyx on the right, Barney behind the G-Man, and Kleiner on the left.
      - **Cages:** each dancer has a `<name>_wind_cage` `func_clip_vphysics` (TOOLSCLIP). Its interior is a tight 64×64 around the dancer, with a ceiling at z 152. Physics objects collide with it; players don't.
      - **Lifts:** each dancer has a `<name>_wind_lift` `trigger_push` (up, speed 1000, z 0..120, flags 8+1024+4096 so every bone of the debris ragdoll is pushed, starts disabled).
      - **Beat:** one oscillating `logic_timer`, `dance_beat_timer` (fixed `RefireTime` 0.3, so a 0.6 s beat, about 100 BPM), drives all lifts. Group A (G-Man and Kleiner) is lifted on the high half of the beat, and group B (Alyx and Barney) on the low half, so the bounces alternate in rhythm.
      - **Sway:** `dance_gust_timer` (fixed 1.2 s, two beats) swings every `dance_wind_gust` trigger (speed 150) between east and west.
      - **Twitch:** `dance_boogie_timer` (every 4.8 s, eight beats) and a `logic_auto` fire `dancing_*` → `StartRagdollBoogie 1.2`, so the electric twitch lands as a short accent on the bar rather than drowning out the bounce.
      - **Balls:** one soccer ball per dancer cage, `dance_ball_<dancer>` (`prop_physics_multiplayer`), bounced by that dancer's lift on the same beat.
      - **Balloons were tried and removed (2026-09-27).** Hand-held balloons (`prop_physics` in an upward `trigger_push`, tied to the hand bones with `constraint.Rope` in a server script) showed no rope and sat on the floor in the live test. The script and entities are gone. If balloons come back, find out first why the rope and lift failed: check whether `InitPostEntity` ran before the ragdoll's physics bones existed, and whether the filtered `trigger_push` ever acted on them.
      - **Tuning:** the push strengths and beat are first guesses. Tune them live, then write the final values back to both VMFs:
        - `ent_fire dance_beat_timer RefireTime 0.25` changes the tempo;
        - `ent_fire gman_wind_lift AddOutput "speed 1200"` changes one dancer's bounce height.
      - Phase G acceptance checks the result from `credits_camera`.
    - **The skybox shell was quick-hidden, so the launchers leaked.** VBSP (and Hammer's compile) skips hidden objects. The 6 TOOLSSKYBOX brushes are now unhidden in both VMFs. Don't quick-hide sealing brushes; use a visgroup that stays shown, or accept seeing them.
    - **Staged launchers.** Both launchers were recompiled (vbsp/vvis/vrad, with the rig) into `generated/launcher_build` and staged to `content/maps` and `garrysmod/maps` on 2026-09-27. `garrysmod/maps` takes precedence over the gamemode's `content/maps`, so the compile script must update both, or a stale copy there shadows the new build. VBSP's "Skybox vtf files for skybox/sky_day01_01 weren't compiled with the same size" `*** Error` is only the default-cubemap warning and is benign. The compile script (Phase C) should fail on a nonzero exit or `leaked`, not on that line.
- **Credits approach (decided by the launcher edit and the credits brief).** The credits open on `credits_camera` in the credits area, with the menu hidden and a vertical crawl over the scene. From there, a Lua-driven camera cycles through the dancers, following the shot sequence in Phase G. `credits_camera` is the room shot the camera returns to. `point_viewcontrol`/`path_track` rigging is rejected, because the targets are moving physics ragdolls that a fixed track can't follow. Spike items:
  - **Dancer discovery.** `targetname` isn't networked, and `ents.FindByName` only works on the server. The server must find the `dancing_*` ragdolls and send their entity indexes and names to the client with the launcher scene pose. The client must not guess by class or model.
  - **Tracking point.** Record which bone reads best as the orbit centre on each model (`ValveBiped.Bip01_Spine2` for the body, `ValveBiped.Bip01_Head1` for the close-up), and confirm that all four models have them. `WorldSpaceCenter` is the fallback. Measure how much the wind rig makes the point jump per frame, to size the smoothing in Phase G.
  - **Face posing.** Confirm that server-side `SetFlexWeight` on a `prop_ragdoll` reaches the client and survives the wind rig and `StartRagdollBoogie`. This is what the Face Poser tool does. For each model, dump its flex controllers (`GetFlexNum`, `GetFlexName`, `GetFlexBounds`) and record the smile set. Candidates on HL2 faces: `smile`, `right_corner_puller`/`left_corner_puller`, `right_cheek_raiser`/`left_cheek_raiser`, a little `jaw_drop`/`right_part`/`left_part` for an open grin, and `right_lid_closer`/`left_lid_closer` at a low weight for smiling eyes. The G-Man model's flex set may differ, so confirm it separately. Also record whether `SetEyeTarget` works on these ragdolls, so the dancers can look into the lens during the orbit.
  - **Orbit clearance.** Barney's cage (x -168..-104) sits close to the west brick wall (x -192), next to the G-Man, and each cage holds a bouncing ball. Record the largest clear orbit radius and height per dancer, and which arcs hit a wall or pass through another dancer.
- **Remote camera feasibility.** Rendering the menu and credits from authored cameras is a `CalcView` override on the client, using a pose the server reads by `targetname` and sends on launcher status. Record and test:
  - **Network visibility.** Entities are sent by the player's PVS, not the view. While the credits view is active, the server must add the camera origin and every dancer's origin through `SetupPlayerVisibility`/`AddOriginToPVS`, or the dancers and props in the credits area may not reach the client. The server doesn't know where the Lua camera is at any moment, so it covers the whole area.
  - **Player state.** The player is frozen, has god mode, is hidden from the view (`drawviewer = false`), and has no weapons in the launcher. HUD, crosshair, and view model are suppressed.
  - **Fog.** `point_camera` fog keys only apply to its monitor render target. Apply the camera's fog values through `SetupWorldFog` while the credits view is active. Disable `ZM_Atmosphere` cell fog and colour correction on launcher maps (see the Alpha 2.9 atmosphere audit), because they would otherwise stack on top.
- **Exit to GMod.** Confirm the behaviour of `RunConsoleCommand("disconnect")` on a listen server and on a dedicated server (on a listen server it stops the local server and returns to the main menu). Nothing needs saving in the launcher because no character state is loaded; confirm this.
- **Scope questions to settle:** whether an in-game "switch character / return to menu" action is in scope (default: deferred, because it needs a changelevel to the launcher), controller support (default: keyboard and mouse only), and menu music (default: ambient loop from GMod or original content only).
- **Developer fast path.** Define a developer convar (for example `zombiesim_dev_autoload_character <slot>`) that skips the menu and loads a slot. Preview iteration must not become slower.
- **Acceptance:** each decision above is recorded here with its chosen option. Both spikes (appearance, globe) have measured results. The migration design lists every affected table and call site. No implementation beyond throwaway spikes has started.

**Phase A status (2026-09-27):** Profile-scoped slots, composite owner migration, keyboard/mouse-only controls, no menu music asset, and fictional static geographic anchors are the current implementation choices. The appearance-model range, globe frame time, PVS, bone/flex controllers, orbit clearance, and listen/dedicated disconnect behavior still require in-engine measurements. Implementation proceeded ahead of those measurements; this phase has **not** passed its original gate.

### Phase B: Character Persistence Foundation

- Add the `characters` table (slot, `characterId`, name, profile, model, skin, bodygroups, player colour, job, origin cell and geographic offset, `createdAt`, `lastPlayedAt`, `appearanceRequired` flag) and the active-character record, with the schema version and migration from Phase A.
- Migrate every character-owned table to the character key. Move the per-SteamID bio to a per-character bio. Make the migration idempotent and transactional, and take a `sv.db` backup copy before the first run. Log migrated row counts per table.
- Add `ply:GetCharacterKey()` and route all 53 persistence call sites through it. Guarantee the `no_character` state cannot save: `Save`, `UpdatePlayerData`, inventory, credit, and trade writes all refuse, with a clear error, while no character is active.
- Add server APIs: list characters (summary only), create, select, delete, and set appearance. Each validates slot range, ownership, the three-slot limit, profile, and state, and deletion is transactional.
- Add a `zn_test_characters` suite using `ZM_TestHarness`, covering:
  - migration idempotence on a copied database, and zero row loss;
  - slot isolation: inventory, credits, and den stash of slot 2 are invisible to slot 1;
  - the slot limit;
  - delete removes every character-owned row and nothing else;
  - the active character survives a simulated respawn;
  - saving is refused with no active character;
  - trading and profession records attribute to the right character.
- **Acceptance:** the suite passes, plus the existing inventory, trading, professions, credits, mastercraft, and implants suites. After migrating a copy of the live `sv.db`, a returning player's slot 1 shows identical XP, level, cash, inventory, credits, and cell, verified with `zombiesim_player_status` in a live client.

**Phase B implementation status (2026-09-27):** The slot roster, active-selection record, character-key routing, one-time rekeying, backup prerequisite, guarded writes, creation/deletion APIs and `zn_test_characters` are implemented. The migration uses the option-2 composite owner key documented above rather than SQLite table rebuilds. GLua syntax passes, but the actual `sv.db` backup does not yet exist, the migration has not run against a copied or installed database, and neither `zn_test_characters` nor the regression suites has run in-engine. Phase B is **pending acceptance**.

### Phase C: Launcher Flow and Menu Shell

- Replace `createLauncherBeginPrompt` with the main menu while keeping the Volt/Walker dependency briefings ahead of it. Move the launcher hold/resume onto the Phase A state machine. `ContinuePlayerSpawnMapTransition` runs only after a character is selected and its state has loaded on the server.
- **Launcher build and scene service.**
  - Add a launcher compile script (for example `bin/build_launchers.ps1 -WorldProfile preview|city`). It compiles only the launcher VMF with VBSP/VVIS/VRAD into `generated/launcher_build`, stages the BSP to `content/maps` and the game's `maps`, and uses `System.Diagnostics.Process` for the compilers. It fails on a leak.
  - Extend `test_map_naming.ps1`, or add a check, so both launcher VMFs must contain the same named scene entities (`credits_camera`, `menu_camera`, `menu_globe`, the G-Man) and differ only in `world_profile`.
  - On launcher maps, the server resolves the named scene entities once, then includes their poses (origin, angles, FOV, fog) in launcher status. It freezes the player and gives god mode, and adds the credits camera to the player's PVS while credits play. The client owns a `CalcView` override that switches between the menu view and the credits view with an eased cut, and leaves normal camera modes untouched off the launcher.
  - Replace the full-screen launcher blackout with a short fade-in to the menu view once the scene is ready. Keep the blackout only as the fallback when a scene entity is missing, and log which one.
- Build the menu as a Derma layer over the live `menu_camera` view of the menu room:
  - large uppercase options stacked on the left (Load Character, New Character, Options, Credits, Exit to GMod), with hover/selection highlight, a slide/fade transition between pages, and UI sounds;
  - the right half of the view is kept clear for the globe, which is a placeholder until Phase F;
  - keyboard navigation (up/down/enter/escape) and mouse.
  - It suppresses the HUD, quick menu, world map, and scoreboard while open, and integrates with `ZM_UI` exclusivity.
- **Options:** refactor the body of `ZM_Options:Open` into a shared builder (for example `ZM_Options:BuildPanel(parent)`) so the radial menu frame and the main menu page show the same controls, with no duplicated option code. Walker settings keep their server permission gate.
- **Exit to GMod:** confirm, then disconnect.
- Add the developer autoload convar from Phase A.
- **Acceptance:** both launchers compile without a leak through the new script, and the staged BSPs contain the new rooms. Then, in a live client on both `zn_preview_start` and `zn_city_start`:
  - the menu view comes from `menu_camera`, or from the documented fallback if it hasn't been placed, with no player model, view model, HUD, or cell fog visible;
  - the dependency briefings still appear when due;
  - the menu opens without the old BEGIN prompt;
  - every entry navigates and returns with keyboard and mouse;
  - Options changes persist and match the radial menu;
  - Exit returns to the GMod main menu;
  - no HUD or radial elements leak through;
  - reconnecting shows the menu again.

### Phase D: Load Character Screen

- Show three slots with a name, profession, level, player model preview (the existing scoreboard model preview pattern), city, and last played time. Empty slots offer "Create". Migrated characters that still need an appearance are marked and routed into the appearance step.
- Selecting a character asks the server to load that slot. The server loads its state, records it as active, sends player data and attributes, and deploys through the existing transition. Show progress and failure states; the screen never waits forever on a lost response.
- Deletion follows the Phase A rule (typed-name confirmation, launcher only), and the slot list refreshes from the server afterwards.
- **Acceptance:** live client:
  - load each of three characters and confirm each deploys to its own cell with its own inventory;
  - delete a character and confirm its slot is empty after a reconnect;
  - a failed or cancelled load returns to the menu with nothing saved;
  - `zombiesim_player_status` confirms the persisted cell and safe zone for the loaded character after a level change.

### Phase E: New Character Flow and Player Models

- A step-based flow with back navigation and a progress indicator, in this order:
  1. slot;
  2. name;
  3. appearance (gender and model from the allowlist, skin, bodygroups, player colour, and a rotating model preview);
  4. profession (from `profession_definitions.json`, with its description, stat bonuses, services, and deliveries);
  5. starting points (spend the pool across the allowed attributes, showing profession bonuses separately);
  6. review;
  7. confirm.
- The server revalidates the whole submission on confirm: name, allowlisted model/skin/bodygroups, known profession, and exact point totals and caps. It then creates the character in one transaction, starts it at the origin safe zone, and records its geographic origin. The client never sends derived values the server can compute.
- Implement `GM:PlayerSetModel` (and hands via `player_manager.TranslatePlayerHands`) from the active character's appearance, so the player has a model in every map and after every respawn.
- **Acceptance:**
  - Live client: create a character in every slot using different professions and models, and confirm the model is correct in first person hands, third person, the scoreboard preview, after death/respawn, and after a cell transition.
  - Automated tests: submissions that overspend points, choose an unknown model, an unknown profession, an invalid name, or a full slot are all rejected with no rows written.

**Phases C–E implementation status (2026-09-27):** Launcher Lua now holds players without loading an active slot, keeps dependency briefings, opens a server-backed menu, supports three-slot listing/creation/appearance/selection/deletion, and hydrates the selected slot before map transition. Creation validates the full payload and stores appearance, profession, starting attributes and origin in one SQLite transaction. Active slots reload on non-launcher spawns; appearance is applied to model and hands. Shared Options controls are reused. The globe and credits were subsequently implemented in Phases F–G. GLua syntax check passes; in-engine `zn_test_characters`, launcher/client UI, model/hand, persistence and level-transition acceptance checks have **not** been run, so C–E are not yet accepted.

### Phase F: Globe

- Render the globe chosen in Phase A in the menu room at `menu_globe`, framed on the right of the `menu_camera` view:
  - smooth, frame-rate-independent rotation with a slight axial tilt;
  - Lua-controlled key and rim lighting;
  - a Cities XL-style look: a dark night side with glowing city lights, a soft blue atmosphere halo, and a lit day side;
  - a gentle idle float.
  - It must not depend on the menu room's baked lighting, and it must read clearly against the fake-fog walls.
- Add a dot for each character at its geographic origin. The selected character's dot pulses and the globe eases round to face it; other characters' dots are dimmer. Label the city on hover or selection.
- Provide a quality path: a lower texture size and simpler shading on low settings, and pausing the render when the menu is hidden.
- **Acceptance:** live client at 1080p:
  - the globe holds the measured frame-time budget from Phase A;
  - no seam or pole artefacts are visible at the menu size;
  - the dots sit at the configured coordinates (check one known latitude/longitude against the texture);
  - selecting each character rotates the globe to its dot;
  - the menu stays responsive during rotation.

**Phase F implementation (2026-09-27):** Original vertex-coloured procedural mesh with animated key/night lighting, city-light hints, blue halo, low-detail convar, and per-profile anchors and slot dots. New characters persist their static-anchor coordinates; legacy characters without them fall back to the anchor. No texture file, RT, world regeneration, or launcher BSP changed. GLua parses; frame time, seam/pole appearance, placement, dot orientation, and interaction remain **unverified in-client**. Anchors are fictional presentation coordinates, not confirmed real-world locations.

### Phase G: Credits

- Credits data (team, contributors, third-party assets and licences, including the globe texture) in a single maintained file, with a vertical crawl that ends or can be skipped with escape or click.
- Selecting Credits hides the menu, fades to black, cuts to `credits_camera` in the credits area, and fades in. It applies that camera's fog, and adds its origin and every dancer's origin to the player's PVS for the duration. The crawl runs over the scene. On end or skip, it fades back to the menu view.
- **The dancers:** the G-Man, Alyx, Barney, and Kleiner dance under the three coloured spotlights, driven by the Hammer wind rig recorded in Phase A. An optional client `DynamicLight` pulse can be synced to the spotlight colours so the baked lights feel alive. It is capped at three dynamic lights and removed when the credits end.
- **Big smiles (server, launcher maps only).** On `InitPostEntity`, and again after each `StartRagdollBoogie` if the spike shows that the boogie resets flexes:
  - apply each dancer's smile preset, a table in the launcher scene service keyed by model and holding flex name → weight, using the flex set recorded in Phase A;
  - look flexes up with `GetFlexIDByName` and skip missing names, so a model without a controller still gets a partial smile instead of a Lua error;
  - clamp weights to `GetFlexBounds` and set `SetFlexScale(1)`;
  - optionally aim the dancers' eyes at the camera with `SetEyeTarget` during their close-up.
  - Faces stay posed for the whole credits and never reset when a shot changes.
- **Credits camera director (client, `cl_launcher_credits.lua` or the launcher scene module).** A small state machine drives `CalcView` from a data-driven shot table. It is timed with `RealTime()`, so it runs at the same speed at any frame rate and pauses cleanly.
  1. **Room:** hold on the `credits_camera` pose with a slow drift (a few degrees of yaw plus a small dolly), for about 4 s.
  2. **Push in:** ease the position, the look-at, and the FOV (90 → about 45) from the room pose to a close-up framing the dancer's head and chest, over about 2.5 s. Use smoothstep or ease-in-out cubic, not linear.
  3. **Orbit:** circle the dancer about 300–360° over about 6–8 s. Look at the smoothed head bone. Radius and height come from the Phase A clearance table, with a gentle bob in height so it doesn't feel mechanical. Arcs recorded as blocked are skipped by reversing direction or shortening the sweep.
  4. **Pull out:** ease back to the room pose and FOV over about 2.5 s, hold briefly, then pick the next dancer. Shuffle the order so no dancer repeats until all four have had a close-up, and never pick the same dancer twice in a row across cycles.
- **Tracking and safety rules for the director:**
  - Follow a smoothed target, not the raw bone position. Use a critically damped spring or exponential smoothing, tuned from the Phase A jitter measurement, so the camera doesn't shake with every wind pulse. Clamp how fast the target can move vertically.
  - Every frame, trace from the target to the desired camera position with `MASK_VISIBLE`. The cage and push brushes are clip/trigger only, so they don't block this trace. If a wall is hit, pull the camera in to the hit point minus a margin, down to a minimum radius.
  - If a dancer becomes invalid (removed, or leaves the PVS), skip to the pull-out and pick another. With no valid dancers, stay on the room shot.
  - Skipping or ending the credits cuts straight to the fade and never waits for a shot to finish.
  - Keep the crawl readable: the close-up keeps the subject off the crawl column (for example, framed a little to the left when the crawl is centred or on the right), and the crawl has a soft backdrop gradient.
  - Developer convars: `zombiesim_credits_shot <dancer>` locks the camera on one dancer for tuning, and `zombiesim_credits_debug 1` draws the orbit path, the target, and the trace hits.
- **Acceptance:** live client:
  - credits run end to end and can be skipped at any point, including mid-orbit;
  - the credits open on the authored `credits_camera` framing, with all four dancers visible, dancing, and present on the client (proving the PVS addition);
  - over one full cycle, each dancer gets a push-in, an orbit, and a pull-out without the camera entering a wall, passing through a ragdoll, or visibly jittering with the wind pulses;
  - every dancer has a visible big smile that lasts through bouncing and boogie pulses, and no flex lookup errors appear in the console;
  - the camera speed is the same at a 30 FPS cap and uncapped;
  - the camera's fog applies only during credits;
  - leaving restores the menu, the globe state, and the menu camera;
  - every shipped third-party asset is listed with its licence.

**Phase G implementation (2026-09-27):** Maintained crawl in `content/data_static/launcher_scene.json`, server-owned scene pose/dancer indexes/PVS, model-keyed guarded flex presets reapplied on a two-second timer, camera room/push/orbit/pull sequence with smoothed target and clearance trace, skip/return and credits-only fog. The server reports actual camera fog keys. GLua parses; `zn_test_characters` now includes an anchor/data case but has **not** run in-engine. Dancer flex availability/replication, safe orbit arcs, fog, frame rate, skip/restart, and visual crawl remain **unverified in a running client**. Actual contributor names and third-party licence inventory need confirmation before final credits acceptance; the crawl currently credits only known engine/model providers and original project work. Optional coloured dynamic lights and eye tracking were not added (no live pose/clearance evidence).

### Phase H: Menu Lighting, Atmosphere, and Polish

- Tune the menu scene: background treatment behind the options (vignette, subtle noise/scanlines in the BO2 spirit, all original), lighting on the globe, and page-transition and selection animation timing. Add sound cues for hover, select, back, and confirm.
- Check scaling and layout at 1280x720, 1366x768, 1920x1080, and 2560x1440, and at the smallest supported UI scale.
- Measure the menu's frame time and memory, and make sure closing the menu frees the globe render target and materials.
- **Acceptance:** live client: no clipped or overlapping text at the listed resolutions; the menu stays within the frame-time budget; repeated open/close and credits loops don't grow memory; all sounds and animations can be interrupted without leaving stuck states.

**Phase H implementation (2026-09-27):** Added an original edge vignette/header line treatment, a short interruptible content fade, a restrained menu accent pulse, responsive panel sizing, built-in button hover/select/back/confirm cues, and brighter ambient globe shading. Globe vertex lighting no longer allocates a direction vector and colour tables per vertex. Credits exit timers are generation-guarded so an older fade cannot finish a later credits run. The globe does not create a render target; its two named materials and finite detail-level geometry caches are reused at module scope rather than allocated per open. `bin/test_glua_syntax.ps1` passed (117 files, 0 failures); this is a code/static result only. Resolution-by-resolution layout, smallest-scale clipping, sound playback, interruption behavior, frame time, and repeated open/close memory use remain **unverified in a running client**; no frame-time budget or live UX claim is made.

### Phase I: Integration, Regression, and Readiness

- Run the GLua syntax check, `zn_test_characters`, and the existing inventory, trading, professions, credits, mastercraft, implants, loot, and static-data suites.
- Run the live matrix:
  - a fresh player with no save;
  - a migrated existing player;
  - three characters in one profile;
  - characters in both `city` and `preview`;
  - death and respawn;
  - cell transition;
  - reconnect;
  - direct join to a cell map with no active character;
  - Exit to GMod;
  - dependency briefings still firing when due.
- Confirm the `sv.db` backup exists and migration logs match row counts. Confirm with repository status and timestamps that no world plans, VMFs, BSPs, or runtime world JSON changed. Only the two launcher VMFs and their BSPs may change, and both BSPs must be built from the current VMFs.
- Update [docs.md](docs.md), [readme.md](readme.md), and [docs/gdd.md](docs/gdd.md) for the character system, launcher menu, developer autoload convar, and credits data. Then update [AGENTS.md](AGENTS.md) so Alpha 2.9 becomes the active tracker.
- **Acceptance:** all listed suites pass; every live-matrix row is recorded as passed or explicitly deferred; no world artefacts changed; documentation reflects the shipped behaviour.

**Integration status (2026-09-27):** Both launcher VMFs passed scene-entity parity and compiled separately with VBSP/VVIS/VRAD; the resulting BSP hashes match both staged locations. The offline GLua syntax check passed (117 files, zero failures). The installed Garry's Mod client/server was not running for this pass. The live `sv.db` has **not** been migrated or backed up by the new startup path, and none of the in-engine test suites or live-matrix rows has passed. Phase B and Phases C–I remain **pending acceptance**, not shipped. Before live migration, copy and inspect the current `sv.db`, verify that startup creates `data/zombiesim/backups/sv_db_alpha_2_8_5_backup.json`, then run `zn_test_characters` and the existing suites. Do not advance the active tracker to Alpha 2.9 until the results are recorded.

**Live session 1 (2026-09-27, `zn_preview_start`):**
- Startup fixes found live:
  - Lua can't read `sv.db`, so the byte-copy backup was replaced by a logical SQLite export with row-count verification.
  - The migration now skips `BOT` and `STEAM_TEST:*` fixture owner keys.
  - The `SetupMove` stamina hook now waits until a character is loaded.
  - The `zn_*` entities now derive from `base_anim` instead of Sandbox-only `base_gmodentity`.
- **Passed:**
  - The migration committed. Two slot-1 characters were created (`city`, `preview`) and the row counts matched an offline dry run: `player_attributes` 2, `player_data` 2, `player_items` 1, `equipped_weapon_slots` 3, `profession_claims` 1, `player_credits` 1, `credit_ledger` 3, `mastercraft_attempts` 1, `trade_ledger` 16.
  - The launcher menu appears and looks correct.
  - The credits sequence works.
- **Retest:** the globe rendered as an opaque, watery blue sphere. The triangles were wound backwards, so the inside of the far hemisphere was visible, with a halo drawn over it. The winding and the halo are corrected but not yet re-seen.
- **Still pending:** `zn_test_characters` and the regression suites, the loot checks (`zn_validate_loot`, `zn_test_loot_spots`), character create/select/deploy, appearance and hands, and delete/disconnect behaviour.

## Cross-Phase Rules

- Phase A gates everything. Phase B gates C–E, because no screen may write character data before the character key and migration exist. Phase F can start after Phase C's shell exists, alongside Phases D and E. Phases G and H follow F.
- Never ship a partial migration: the schema change, call-site routing, and tests from Phase B land together. Keep a restorable `sv.db` copy from before the first migration run.
- The menu never decides an outcome. Slot limits, names, appearance validity, points, profession, deletion, and the active character are all server decisions.
- The launcher must always be escapable. Every step has back/cancel, and a lost or failed server response returns to the menu with an error rather than locking input.
- Client presentation (globe, credits, animation) must not delay or block deployment once a character is selected.
- Mark a phase complete only after its acceptance checks pass; clearly label static-only verification or live blockers.

## Scope Coverage

- Launcher menu replacing the BEGIN prompt, BO2-style layout and motion, Options mirror, Exit to GMod: Phases A, C, H, and I.
- Up to three character slots, load, create in an empty slot, and delete: Phases A, B, D, and I.
- New character flow (slot, appearance with gender and facial features, profession, starting points, review, confirm, save to slot): Phases A, B, and E.
- Missing player model fix: Phases A (appearance spike), B (migrated characters flagged for appearance), and E (`PlayerSetModel` and hands).
- Rotating globe, its lighting and atmosphere, and the Cities XL-style look: Phases A, F, and H.
- Character location dots from where the character was created: Phases A (geographic model), B (stored origin), E (recorded at creation), and F (drawn on the globe).
- Scrolling credits with the menu hidden, played in the Hammer-authored credits area: Phases A, C, and G.
- Dancing G-Man and friends (Hammer wind rig), the camera director (room → push-in → orbit → pull-out → next dancer), and smiling faces: Phases A (dancer discovery, bones, flex set, orbit clearance) and G.
- Launcher menu room, credits area, named camera and globe markers, and the launcher compile: Phases A, C, and I.
- Menu lighting and atmosphere, performance balance: Phases A, F, and H.