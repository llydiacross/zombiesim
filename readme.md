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

For each cubemap map, run `buildcubemaps` in your console. After its level reload, run `zombiesim_map_batch_next` to load the next map. For each navmesh map, run `nav_generate`, then `nav_save`; after both finish, run `zombiesim_map_batch_complete`. Use `zombiesim_map_batch_status` to view progress or `zombiesim_map_batch_cancel` to stop.

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

The portable C++20 simulator lives in [bin/walker-simulator](bin/walker-simulator). `walker_core` is the only importer and simulation implementation: the optional GMod module and standalone observer are hosts around the same core, world JSON, configuration, and deterministic command stream.

## Current Behavior

- The generator exports one `world.population` budget. The preview world has 81,000 virtual walkers and the city has 310,200; the core allocates that exact total across non-safe cells.
- The GMod module runs one optional worker at 4 Hz. Horde progress is 4 permille per tick, so an unimpeded horde crosses one logical cell in 62.5 seconds.
- The preview-only `WALKER` world-map mode receives native horde summaries every 0.5 seconds and renders them. It does not simulate a second client-side world.
- No NPC materialization, spawn anchors, spawn tickets in GMod gameplay, or loot integration exists yet. The worker is currently an abstract population simulation plus diagnostics.

## State And Persistence

`walker_core` can export and import validated, checksummed checkpoints, and its test suite covers that format. The active GMod adapter does **not** currently expose checkpoint save or restore, however: it builds a new simulation from the selected runtime JSON at level initialization and discards it during `ShutDown`.

Consequently, Walker state is not yet preserved across a `changelevel`, server restart, or a fresh server after everyone reconnects. Player persistence is separate and does not preserve virtual walkers. A later persistence implementation must save one per-profile native checkpoint to GMod's `DATA/zombiesim` mount at a completed worker tick, validate its graph/config hashes on load, and start fresh only when the checkpoint is absent or invalid.

A desktop viewer must remain read-only or attach to one authoritative state owner. Running an independent `.exe` against the same JSON creates a separate deterministic replay; it must not write a checkpoint that GMod also writes. To let time advance while GMod is closed, make the viewer the deliberate offline owner of a per-profile checkpoint, then have GMod import that checkpoint on its next startup. Simultaneous GMod and viewer control requires an explicit IPC service and is not implemented.

## Build And Test

Run these commands from [bin/walker-simulator](bin/walker-simulator). The workspace's supported toolchain is CMake, Ninja, and MinGW:

```powershell
cmake --preset mingw-debug
cmake --build --preset build-mingw-debug
ctest --preset test-mingw-debug
```

The command-line observer replays an exported world/config/command log through `walker_core`; it is not a persistent live-world editor.

```powershell
.\build\mingw-debug\zombiesim-walker-observer.exe `
   --world .\tests\fixtures\preview-world.json `
   --profile preview `
   --config .\tests\fixtures\walker-config-v1.json `
   --command-log .\tests\fixtures\command-log-basic.jsonl `
   --ticks 16
```

To build the optional Windows x64 server module and run its ABI diagnostic:

```powershell
cmake --preset mingw-gmod-module-debug
cmake --build --preset build-mingw-gmod-module-debug
.\scripts\install-local-win64.ps1 -GarrysModRoot "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```

`zombiesim_walker_smoke` remains useful after the prior Win64 ABI failure, but it verifies only module loading, the Lua ABI, and the core self-test. It does not load a world, start the worker, persist state, or prove gameplay integration. Use `zombiesim_walker_status` and `zombiesim_walker_noise <strength> <radius> [durationTicks]` to diagnose the live worker. The external loader and DLL can be removed with `scripts/uninstall-local-win64.ps1`.

The module must use the vendored Facepunch `gmod-module-base` `development` revision; its Win64 `ILuaBase` offset assertion protects against the legacy `master` layout that crashes during module load.

Garry's Mod Workshop uploads made with `gmad` cannot distribute the Walker DLL. Publish the built binary as a GitHub Release asset and install it manually under `garrysmod/lua/bin` using the installer above. 

```powershell
.\scripts\install-local-win64.ps1 -GarrysModRoot "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```


When a launcher map reports that the server module is absent, Z-Nation shows a `MISSING DLL` prompt with a link to the releases page. Separately, the first client startup without Volt VPhysics shows an optional link to its GMod build page; its client process checks Volt's `vjolt_substeps` console variable and never changes gameplay behavior.
