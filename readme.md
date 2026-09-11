# Zombiesim



Based upon Dead Frontier In Gmod.

- Each map is a "cell" which makes up the entire city. The further you go into the city, the harder the enemies, greater the loot. Rarer loot also drops in further regions.
- Based off of dead frontier
- Top Down third person, zombie survival looter in gmod
- Players start at the den (x 0, y 0) in the city and can venture further
- The city is a grid of cells
- Each cell is just a .vmf file containing a map, a map is made up of a cunk
- When you go trigger a transition by walking down to road to the next map, if you are going north and you are at say for instance (x 0, y 0), your new map position will be (x 0, y 1). 
- A small map contains 5x5 chunks, (a chunk is 640*640 hammer units wide), a large map 50x50, and an extremely large map 100x100.
- The maps are made up of prefabs to speed up the development, a prefab is a chunk wide.
- These prefabs can be buildings, roads, anything really, they are 640*640 units wide the size of a chunk and are made by hand
- would be cool to have an algorithm that can generate cities

# Folder Structure

- ./tiletemplates
   - the pieces (chunks) for making the cells, usually each file is just 1 chunk wide
- ./content
   - data read by gmod

Further into content is the `maps/city` folder

These are compiled reusable recipe maps for the city. A recipe can serve more than one logical city cell, so its filename does not identify a coordinate.

`content/data_static/zombiesim_world.json` maps every cell coordinate to its selected recipe BSP and provides the navigation graph and gameplay metadata. Build a transition map name from `world.mapDirectory .. "/" .. cell.map`; it is the authoritative lookup for map transitions.

Recipe BSPs use the generated VMF basename, for example `zn_grassland_open_none.bsp`.

# Powershell Commands

Run these from the project root. The preview profile is isolated from production and stages its playable maps in `content/maps/preview`.

Generate the deterministic preview world image, manifest, and map layers:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
```

Plan its recipes and write the required-map list:

```powershell
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json
```

Refresh the generated recipe VMFs, prune obsolete generated files, and verify every required recipe exists:

```powershell
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -WorldProfile preview
```

Generate Hammer-only template zoos in `celltemplates/dev`. `-RefreshPlan` first replans the preview so `streets.vmf` and `carparks.vmf` reflect current placement rules; `landmarks.vmf` lists every template matched by `cellPlanning.landmarkTemplatePatterns` in `generator-settings.json` and automatically includes future configured landmark templates:

```powershell
.\bin\build_tile_zoos.ps1 -RefreshPlan
```

Create or refresh portal files for every required city recipe and standalone den map, then report portal and cluster budget violations. Valid current portal data is reused; only missing, invalid, or source-stale maps run through VBSP. This must run first when using `-PrioritizePortalCost`; add `-ForcePortalData` for a full portal rebuild:

```powershell
.\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
```

Render and stage a finished preview from existing validated BSPs. It runs the largest portal workloads first and skips VVIS/VRAD stages that already completed; add `-Force` for a clean rerun of both stages:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -PrioritizePortalCost -CleanStagedCity -VvisTimeoutSeconds 1800 -VradTimeoutSeconds 3600
```

Run a complete clean preview build, including fresh BSPs, visibility, lighting, and staging:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -Force  -CleanStagedCity -VvisTimeoutSeconds 1800 -VradTimeoutSeconds 3600
```

## Export To Garry's Mod

This workspace is already installed inside Garry's Mod under `garrysmod/gamemodes/zombiesim`. The export commands stage the selected compiled BSPs, generated map materials, and matching runtime-world JSON into this gamemode's `content` directory. Use the profile-wide command instead of copying individual BSPs so map files, satellite materials, and runtime references stay synchronized.

Export an already compiled preview without running VBSP, VVIS, or VRAD again:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipCompile -CleanStagedCity
```

This copies the selected preview BSPs from `generated/build_preview` to `content/maps/preview`, stages generated world layers in `content/materials/worlds/preview/map_layers`, renders local recipe maps in `content/materials/worlds/preview/cells`, rebuilds `satellite.png`, and writes `content/data_static/zombiesim_world_preview.json`. `-CleanStagedCity` removes stale BSPs from the selected profile's staging folder.

Stage existing engine-generated navmeshes for the same profile without requiring a BSP rebuild:

```powershell
.\bin\stage_world_navmeshes.ps1 -WorldProfile preview -CleanStagedCity
```

This copies matching `.nav` files from `garrysmod/maps/preview` into `content/maps/preview`. It does not modify the engine's runtime navmesh files.

After rebuilding recipe BSPs, clear the profile's old navmeshes before generating fresh ones in Garry's Mod:

```powershell
.\bin\clear_world_navmeshes.ps1 -WorldProfile preview
```

This removes both engine runtime navmeshes from `garrysmod/maps/preview` and their staged copies. Reload `zn_preview`, run `zombiesim_generate_navmeshes`, then rebuild `wireframe.png` after the batch completes.

Export an already compiled production city with the same process:

```powershell
.\bin\build_city.ps1 -WorldProfile city -OnlyRequiredMaps -SkipRecipeRefresh -SkipCompile -CleanStagedCity
```

The production outputs are `content/maps/city`, `content/materials/worlds/city`, and `content/data_static/zombiesim_world.json`.

To refresh only generated map materials after a visual renderer change, while keeping existing BSPs and runtime data, run:

```powershell
.\bin\stage_world_map_materials.ps1 -WorldProfile preview
.\bin\build_cell_map_materials.ps1 -WorldProfile preview
.\bin\build_world_satellite_material.ps1 -WorldProfile preview
```

When the map manifest or template plan has changed, also refresh the matching runtime index after the required BSPs exist:

```powershell
.\bin\export_runtime_world_data.ps1 -WorldProfile preview -RequireCompiledMaps
```

After staging, reload the `zn_preview` launcher map for the preview profile or `zn_start` for the city profile so Garry's Mod loads the matching staged world index.

Build cubemaps for every unique recipe and safe-zone map in the loaded world profile. Run this from the in-game server console or as an admin; it changes level to the first map and prints the native command to run:

```
zombiesim_build_cubemaps
```

Generate navmeshes for the same map queue:

```
zombiesim_generate_navmeshes
```

The navmesh batch automatically generates and saves navigation data only for ordinary city-cell maps that do not already have a `.nav` file in the active profile. Existing navmeshes are skipped. Clear the profile navmeshes after a BSP rebuild to force a fresh full pass. To generate one missing map first, pass its basename or profile-relative name:

```
zombiesim_generate_navmeshes <mapName>
```

Wireframe materials read existing Source navmesh files directly from `garrysmod/maps/<profile>`; no map transitions are needed to render them:

```powershell
.\bin\build_world_wireframe_material.ps1 -WorldProfile preview
```

Use `zombiesim_navmesh_status` to inspect the loaded map, matching nav file, and nav-area count. Use `zombiesim_map_batch_status` for queue progress, `zombiesim_map_batch_retry` after a failed map, or `zombiesim_map_batch_cancel` to stop. For each cubemap map, run `buildcubemaps` in your console; after its reload, run `zombiesim_map_batch_next` to load the next map.

# In-Game Commands

Run this from an in-game admin console to reset your attributes, progression, health, stamina, and location, then return to the active world's origin den:

```
zombiesim_reset_player
```

Run this from an in-game admin console to print your saved raw grid cell, logical world coordinate, safe-zone id, and map resolution:

```
zombiesim_player_status
```

## Development Command Bridge

For local development, edit [content/data_static/consolecommands.txt](content/data_static/consolecommands.txt). Give every request a new `# request:` identifier and place one server-console command on each uncommented line. The bridge polls the mounted file and executes each identifier once, including across map changes. It is enabled by default only for non-dedicated servers; toggle `zombiesim_dev_console_enabled` to control it.

The bridge writes an acknowledgement and any structured diagnostic data to `garrysmod/data/zombiesim/consolecommands.result.json`. This location is the GMod `DATA` mount, so it is intentionally outside the gamemode source tree. Ordinary engine-console output remains in the game console; use the structured persistence probe for automation:

```
zombiesim_dev_persistence_report STEAM_0:1:31630
```

That report includes the raw `city` and `preview` player/attribute rows, active map and profile, and current live player fields.

## Local Development Session

Use the scripts below from the repository root to start a local ZombieSim session through Steam with the game console, `console.log`, and Source server logs enabled:

```powershell
.\bin\start_zombiesim_dev.ps1 -WorldProfile preview
.\bin\read_zombiesim_dev_log.ps1 -Lines 200
.\bin\send_zombiesim_dev_command.ps1 zombiesim_walker_status
.\bin\stop_zombiesim_dev.ps1
```

`send_zombiesim_dev_command.ps1` overwrites the bridge input with a fresh request id, as required by `sv_dev_console.lua`. Use `read_zombiesim_dev_log.ps1 -Console` for the `-condebug` capture, or add `-Follow` when manually observing an active session. `stop_zombiesim_dev.ps1` closes the local `gmod.exe` window first so the server can run normal shutdown hooks; use `-Force` only when it cannot exit gracefully.

Validate every loaded gamemode and utility Lua file with Garry's Mod's native GLua parser without executing the files:

```
zombiesim_validate_scripts
```

When invoked through the bridge, `consolecommands.result.json` includes `reports.scriptValidation` with the checked, passed, and failed counts plus one result for each source file. Syntax failures are also printed in the server console with their mounted `GAME` path.

# Runtime World Data

`ZM_World` loads `data_static/zombiesim_world.json` from the `GAME` mount during gamemode initialization. It returns `nil` or `false, error` when the index is unavailable, so gameplay code can fail safely while a release is being assembled.

```lua
local cell = ZM_World:GetCell(0, 0)
local mapName = ZM_World:GetMapPath(cell)
local target, exit, mode = ZM_World:CanTravel(cell, "N", "road")
local route = ZM_World:FindPath({ x = 0, y = 0 }, { x = 8, y = 12 }, { mode = "any" })
```

Player helpers use their persisted `CellX` and `CellY` coordinates: `ply:GetWorldCell()`, `ply:GetNeighbouringCell("N")`, `ply:GetNeighbouringCells()`, and `ply:GetReachableNeighbouringCells("road")`. Both British and American `Neighbouring`/`Neighboring` spellings are available.

The service provides cell lookup by coordinates/id/map, map transition resolution, exit and blockade checks, environment/district/safe-zone/landmark/metro/atmosphere data, indexed metadata searches, nearest-cell searches, and A* routing. Recipe map names can refer to multiple logical cells; use `GetCellsForMap` when a map name is ambiguous.

- ./source

The .vmf files for the cells of the city, should match a map file in the content folder idealily.

# Generator Settings

Generation is controlled from [generator-settings.json](generator-settings.json). Start with the plain-language guide in [docs.md](docs.md); it explains every setting, shows the preview workflow, and marks settings that are safe to experiment with.

For future multi-tile prefab support, see [docs/two_by_two_tile_templates_plan.md](docs/two_by_two_tile_templates_plan.md).

# Walker Simulator

The authoritative native population system and its Alpha 2 ticket contract are documented in [docs/walker_simulation.md](docs/walker_simulation.md). Run these commands from [bin/walker-simulator](bin/walker-simulator):

```powershell
cmake --preset mingw-debug
cmake --build --preset build-mingw-debug
ctest --preset test-mingw-debug --output-on-failure
```

Build and install the optional Win64 server module:

```powershell
cmake --preset mingw-gmod-module-debug
cmake --build --preset build-mingw-gmod-module-debug
.\scripts\install-local-win64.ps1 -GarrysModRoot "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```

In game, run `zombiesim_walker_smoke`, load `zn_preview`, then use `zombiesim_walker_status` and `zombiesim_walker_noise <strength> <radius> [durationTicks]`. Record live evidence in [docs/alpha_2_test_log.md](docs/alpha_2_test_log.md).

Compatible Walker checkpoints persist horde movement, attractors, terminal ticket outcomes, and the server ticket-request counter across level changes and restarts. Checkpoints are profile-scoped in the server SQLite `walker_checkpoints` table; periodic serialization runs on the native worker thread. Map-local NextBots are reconciled as despawned after restore, then the materializer resumes normally. Use `zombiesim_walker_checkpoint_status`, `zombiesim_walker_checkpoint_save`, and `zombiesim_walker_checkpoint_clear <profile>` for server-side checkpoint diagnostics and administration. Workshop uploads cannot distribute the DLL; install releases manually under `garrysmod/lua/bin` using the script above.
