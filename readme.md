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

Create or refresh portal files only, then report portal and cluster budget violations, must be ran first to use PrioritizePortalCost flag:

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

 For future multi-tile prefab support, see [two_by_two_tile_templates_plan.md](two_by_two_tile_templates_plan.md).
